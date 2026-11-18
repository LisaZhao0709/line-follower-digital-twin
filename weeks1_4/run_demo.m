function [out,metric]=run_demo(mode,Kp,Kd)
% Examples: run_demo('PD'); run_demo('P',0.45); run_demo('PD',0.45,0.03).
if nargin<1,mode='PD';end
cfg=project_config();
if nargin<2,Kp=cfg.Kp;end
if nargin<3,Kd=cfg.Kd;end
if strcmpi(mode,'P'),Kd=0;else,assert(strcmpi(mode,'PD'),'Mode must be P or PD.');end
build_models();
[out,cfg]=simulate_case('LF_Week4_PD',struct('Kp',Kp,'Kd',Kd));
name=sprintf('demo_%s',upper(mode));
[metric,~]=evaluate_run(out,cfg,name);
plot_run(out,cfg,name,metric);disp(struct2table(metric));
assignin('base','lastRun',out);assignin('base','lastMetric',metric);
open_system(fullfile(cfg.models_dir,'LF_Week4_PD.slx'));
end
