function [out,record,directory]=run_accurate_demo(mode,Kp,Kd)
% Fresh exact-ZOH run with timestamped traces/configuration/model snapshots.
if nargin<1,mode='PD';end
cfg=project_config();if nargin<2,Kp=cfg.Kp;end;if nargin<3,Kd=cfg.Kd;end
if strcmpi(mode,'P'),Kd=0;else,assert(strcmpi(mode,'PD'),'Mode must be P or PD.');end
build_exact_models();
stamp=char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyyMMdd_HHmmss_SSS'));
directory=fullfile(cfg.results_dir,'experiments',['exact_' stamp]);
assert(~isfolder(directory));mkdir(directory);mkdir(fullfile(directory,'figures'));
diary(fullfile(directory,'matlab_run.log'));cleanup=onCleanup(@()diary('off'));
[out,cfg]=simulate_case('LF_Week4_PD_Exact',struct('integration_method','exact_zoh', ...
    'Kp',Kp,'Kd',Kd,'results_dir',directory));
name=['Exact_' upper(mode)];
record=audit_run(out,cfg,name,'LF_Week4_PD_Exact',directory);
copyfile(fullfile(cfg.models_dir,'LF_Week4_PD_Exact.slx'),fullfile(directory,'model_snapshot.slx'));
plot_run(out,cfg,name,record);
assignin('base','lastReviewedRun',out);assignin('base','lastReviewedConfig',cfg);
open_system(fullfile(cfg.models_dir,'LF_Week4_PD_Exact.slx'));
disp(struct2table(record));fprintf('Saved new experiment: %s\n',directory);
end
