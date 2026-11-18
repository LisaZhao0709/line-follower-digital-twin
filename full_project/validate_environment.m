function directory=validate_environment()
% Exercise real Simulink entry points, legacy traces, seeded errors and UI.
cfg=twin_config();directory=fullfile(cfg.results_dir,['environment_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(directory);
diary(fullfile(directory,'matlab.log'));cleanup=onCleanup(@()diary('off'));
randomState=rng;env=twin_environment(twin_config(struct('environment_level',1)));
assert(isequal(randomState,rng),'Environment generation changed global RNG.');
assert(isequal(env,twin_environment(twin_config(struct('environment_level',1)))));
cases={struct(),struct('environment_level',1),struct('environment_level',1), ...
    struct('environment_level',1,'environment_seed',8),struct('environment_level',2), ...
    struct('environment_level',2,'dropout_start_s',1,'dropout_duration_s',.4,'stop_time',3), ...
    struct('sensor_noise',.03,'stop_time',3)};
names={'ideal','mild_seed7','mild_repeat','mild_seed8','strong_seed7','dropout','legacy_sine'};
records=cell(size(names));traces=cell(size(names));
for k=1:numel(names)
    [out,c]=twin_simulate(cases{k});
    [records{k},traces{k}]=twin_record(out,c,names{k},directory);
    assert(all(traces{k}{:,arrayfun(@(j)sprintf('strength%d',j),1:8,'UniformOutput',false)}>=0,'all'));
    assert(all(traces{k}{:,arrayfun(@(j)sprintf('strength%d',j),1:8,'UniformOutput',false)}<=1,'all'));
end
old=readtable(fullfile(twin_latest(5),'PID_default_trace.csv'));
assert(isequal(old.Properties.VariableNames,traces{1}.Properties.VariableNames));
assert(max(abs(old{:,:}-traces{1}{:,:}),[],'all')<1e-12);
assert(records{1}.completed_lap && records{1}.sensor_bit_error_fraction==0);
assert(isequaln(traces{2},traces{3}),'Same seed must reproduce the entire trajectory.');
assert(~isequal(traces{2}.strength4,traces{4}.strength4),'New seed must change observations.');
assert(records{2}.sensor_strength_rmse>0 && records{2}.sensor_bit_error_fraction>0);
assert(records{6}.stop_reason==1 && records{6}.stop_time_s<=1.2+1e-9);
stopped=traces{6}.time_s>=records{6}.stop_time_s;
assert(all(traces{6}.uL(stopped)==0) && all(traces{6}.uR(stopped)==0));
for invalid={struct('environment_seed',NaN),struct('environment_seed',-1), ...
        struct('environment_seed',.5),struct('environment_level',3)}
    rejected=false;try,twin_config(invalid{1});catch,rejected=true;end;assert(rejected);
end
writetable(struct2table([records{:}]),fullfile(directory,'summary.csv'));
fig=figure('Visible','off','Position',[50 50 1080 700]);closeFigure=onCleanup(@()close(fig));
subplot(3,1,1);plot(traces{2}.time_s,traces{2}.ideal_strength4,'--',traces{2}.time_s,traces{2}.strength4);
xlim([0 5]);ylabel('S4 strength');legend('Ideal at same pose','Observed');grid on;
subplot(3,1,2);plot(traces{2}.time_s,traces{2}.env_light_gain,traces{2}.time_s,traces{2}.env_shadow_bias);
ylabel('Optical disturbance');legend('Light gain','Shadow bias');grid on;
subplot(3,1,3);plot(traces{2}.time_s,1000*traces{2}.env_lateral_jitter_m);ylabel('Lateral jitter (mm)');xlabel('Simulation time (s)');grid on;
exportgraphics(fig,fullfile(directory,'environment_comparison.png'),'Resolution',140);
app=twin_app('off');closeUI=onCleanup(@()app.actions.close());
app.environment.Value=2;app.seed.String='7';app.actions.run();q=guidata(app.figure);
assert(isempty(q.error) && q.cfg.environment_level==1 && q.cfg.environment_seed==7);
assert(isequaln(q.trace,traces{2}),'UI must use the same seeded simulation.');
app.actions.step();app.actions.reset();q=guidata(app.figure);assert(q.index==1);
app.seed.String='NaN';app.actions.run();q=guidata(app.figure);assert(~isempty(q.error));
app.actions.close();
twin_write_json(fullfile(directory,'status.json'),struct('passed',true,'actual_simulink_cases',8, ...
    'ideal_matches_frozen_trace',true,'seed_repeat_exact',true,'new_seed_changes_observations',true, ...
    'random_generator_isolated',true,'safety_latch_verified',true,'ui_environment_run_verified',true));
fprintf('ENVIRONMENT_VALIDATION_PASSED %s\n',directory);
end
