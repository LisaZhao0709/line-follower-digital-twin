% Select this file in MATLAB and press Run. First-run builds are automatic.
projectRoot=fileparts(mfilename('fullpath'));
addpath(projectRoot,fullfile(projectRoot,'kernels'));
assert(license('test','Simulink')==1,'Simulink license unavailable.');
fprintf('Starting weeks 1-4 project in %s\n',projectRoot);
build_models();
cfg=project_config();show_map(cfg);
defaultRun=fullfile(cfg.results_dir,'PD_default_run.mat');
if isfile(defaultRun) && isfile(fullfile(cfg.results_dir,'验收结果.md'))
    saved=load(defaultRun,'out','metric');
    plot_run(saved.out,cfg,'PD_default',saved.metric);
    assignin('base','lastRun',saved.out);assignin('base','lastMetric',saved.metric);
    fprintf('Opened saved verified results. Run run_acceptance to repeat validation.\n');
else
    summary=run_acceptance();
end
open_system(fullfile(projectRoot,'models','LF_Week4_PD.slx'));
fprintf('\nReady. Try: run_demo(''P'',0.45), or run_demo(''PD'',0.45,0.03).\n');
