function summary=review_safety_and_lap_tests(directory)
cfg=project_config();addpath(fullfile(cfg.root,'kernels'));
rows={};
clear loss_guard
for k=1:10,[enabled,off,elapsed]=loss_guard(false,.02,.2);assert(enabled==1 && off==0 && elapsed<.2);end
[enabled,off,elapsed]=loss_guard(false,.02,.2);assert(enabled==0 && off==1 && abs(elapsed-.2)<1e-12);
[enabled,off,~]=loss_guard(true,.02,.2);assert(enabled==0 && off==1);
rows(end+1,:)={'loss_full_0p2_seconds_then_latched',true,'11 samples spanning 0.20s latch stop; one good sample cannot restart'};
clear loss_guard
for k=1:5,loss_guard(false,.02,.2);end
loss_guard(true,.02,.2);
for k=1:10,[enabled,off,~]=loss_guard(false,.02,.2);assert(enabled==1 && off==0);end
rows(end+1,:)={'valid_sample_clears_missing_counter',true,'A good sample restarts the consecutive-loss count'};
clear loss_guard
[enabled,off,~]=loss_guard(true,.02,.2);assert(enabled==1 && off==0);
rows(end+1,:)={'fresh_run_clears_stop_latch',true,'Persistent state is cleared for a fresh run'};
% Stationary/short line/teleport traces must never be mistaken for a lap.
t=(0:cfg.Ts:2).';x=repmat(cfg.x0,size(t));y=repmat(cfg.y0,size(t));
r=lap_review(t,x,y,cfg);assert(~r.completed_lap);
rows(end+1,:)={'stationary_is_not_a_lap',true,'No finish from elapsed time alone'};
x=cfg.x0+.01*sin(2*pi*t);r=lap_review(t,x,y,cfg);assert(~r.completed_lap);
rows(end+1,:)={'start_line_wiggle_is_not_a_lap',true,'Crossing near the start without all sectors is rejected'};
% Artificially visit the entire reference in 2 s: violates max possible speed.
indices=round(linspace(1,size(cfg.referenceXY,1),numel(t)));
x=cfg.referenceXY(indices,1);y=cfg.referenceXY(indices,2);
r=lap_review(t,x,y,cfg);assert(~r.completed_lap && r.rejected_spatial_jumps>0);
rows(end+1,:)={'teleported_route_is_not_a_lap',true,'Impossible spatial steps invalidate completion'};
summary=cell2table(rows,'VariableNames',{'check','passed','criterion'});
writetable(summary,fullfile(directory,'safety_and_lap_checks.csv'));
end
