function summary=run_acceptance()
% Four-week acceptance in installed MATLAB/Simulink; no Python substitute.
cfg=project_config();build_models();
fig=show_map(cfg);
assert(~any(cfg.trackMask(1,:)) && ~any(cfg.trackMask(end,:)) ...
    && ~any(cfg.trackMask(:,1)) && ~any(cfg.trackMask(:,end)),'Outer frame remains in map.');
assert(abs(cfg.line_width_m-.02)<1e-12);
week2_open_loop_tests();week3_sensor_tests();
cases={'P_weak',.05,0; 'P_baseline',cfg.Kp,0; 'PD_default',cfg.Kp,cfg.Kd};
metrics=struct([]);runs=cell(1,3);
for k=1:3
    name=cases{k,1};
    [out,c]=simulate_case('LF_Week4_PD',struct('Kp',cases{k,2},'Kd',cases{k,3}));
    [m,~]=evaluate_run(out,c,name);
    if k==1,metrics=m;else,metrics(k)=m;end
    runs{k}=out;
    plot_run(out,c,name,m);
    fprintf('Week4 %s: lap=%d, lap time=%.2f, MAE=%.4f, stopped=%d\n', ...
        name,m.completed_lap,m.lap_time_s,m.mae_sensor_error,m.stopped_off_track);
end
summary=struct2table(metrics);
writetable(summary,fullfile(cfg.results_dir,'week4_comparison.csv'));
assert(metrics(2).completed_lap && ~metrics(2).stopped_off_track,'P baseline failed to follow the full track.');
assert(metrics(3).completed_lap && ~metrics(3).stopped_off_track,'Default PD failed to follow the full track.');
assert(metrics(1).stopped_off_track && ~metrics(1).completed_lap,'Weak P did not demonstrate expected loss.');
assert(all(abs(series_data_only(runs{2},'D_term'))<1e-12),'P run has nonzero D action.');
% Repeatability: a fresh PD run must reproduce the entire state trace.
[repeat,~]=simulate_case('LF_Week4_PD',struct('Kp',cfg.Kp,'Kd',cfg.Kd));
for signal={'x','y','theta','error','uL_log','uR_log'}
    a=series_data_only(runs{3},signal{1});b=series_data_only(repeat,signal{1});
    assert(isequal(size(a),size(b)) && max(abs(a-b),[],'all')<1e-12,'Reset/repeatability failed: %s',signal{1});
end
write_acceptance_report(cfg,summary);
disp(summary);
fprintf('ALL_WEEKS_1_TO_4_ACCEPTANCE_PASSED\n');
end

function data=series_data_only(out,name)
[~,data]=series_data(out,name);
end
