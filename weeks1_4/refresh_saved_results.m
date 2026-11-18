function summary=refresh_saved_results()
% Re-evaluate/export saved actual Simulink traces after an offline reporting change.
cfg=project_config();names={'P_weak','P_baseline','PD_default'};
for k=1:3
    saved=load(fullfile(cfg.results_dir,[names{k} '_run.mat']),'out','cfg');
    [metric,~]=evaluate_run(saved.out,saved.cfg,names{k});
    if k==1,metrics=metric;else,metrics(k)=metric;end
    plot_run(saved.out,saved.cfg,names{k},metric);
end
summary=struct2table(metrics);
assert(summary.completed_lap(2) && summary.completed_lap(3));
assert(~summary.stopped_off_track(2) && ~summary.stopped_off_track(3));
writetable(summary,fullfile(cfg.results_dir,'week4_comparison.csv'));
write_acceptance_report(cfg,summary);disp(summary);
end
