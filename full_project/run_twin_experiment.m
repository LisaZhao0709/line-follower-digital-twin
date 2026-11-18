function [record,trace,cfg,directory]=run_twin_experiment(Kp,Ki,Kd,extra)
% Every experiment gets a new directory; reviewed records are never overwritten.
if nargin<4,extra=struct();end
extra.Kp=Kp;extra.Ki=Ki;extra.Kd=Kd;cfg=twin_config(extra);
directory=fullfile(cfg.results_dir,'experiments',['run_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);mkdir(directory);
diary(fullfile(directory,'matlab.log'));cleaner=onCleanup(@()diary('off'));
try
    [out,cfg]=twin_simulate(extra);[record,trace]=twin_record(out,cfg,'experiment',directory);
    copyfile(fullfile(cfg.models_dir,'LineFollowerTwin.slx'),directory);
    twin_write_json(fullfile(directory,'status.json'),struct('passed',true,'case',record));
catch error
    twin_write_json(fullfile(directory,'status.json'),struct('passed',false,'error',error.message));rethrow(error);
end
end
