% Fast entry: open the reviewed model and its saved actual PD experiment.
projectRoot=fileparts(mfilename('fullpath'));
addpath(projectRoot,fullfile(projectRoot,'kernels'));
reviewDirectory=latest_review_directory();
reviewed=load(fullfile(reviewDirectory,'Exact_PD_20ms_run.mat'),'out','cfg','record');
lastReviewedRun=reviewed.out;lastReviewedConfig=reviewed.cfg;
previewConfig=reviewed.cfg;previewConfig.root=projectRoot;
previewConfig.results_dir=fullfile(projectRoot,'results');
show_map(previewConfig);
plot_run(reviewed.out,previewConfig,'reviewed_PD',reviewed.record);
open_system(fullfile(projectRoot,'models','LF_Week4_PD_Exact.slx'));
fprintf('Reviewed exact-ZOH simulation: %.6f s per lap (interpolated gate time).\n',reviewed.record.lap_time_s);
fprintf('play_reviewed_run shows recorded motion. run_accurate_demo(''PD'',0.45,0.03) starts a fresh experiment.\n');
