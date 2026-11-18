function [out,cfg] = simulate_case(model,overrides)
% Parameterize a run without permanently changing the student's saved model.
if nargin<2,overrides=struct();end
cfg=project_config(overrides);
load_system(fullfile(cfg.models_dir,[model '.slx']));
in=Simulink.SimulationInput(model);
in=in.setVariable('cfg',cfg,'Workspace',model);
in=in.setVariable('Kp',cfg.Kp,'Workspace',model);
in=in.setVariable('Kd',cfg.Kd,'Workspace',model);
in=in.setModelParameter('StopTime',num2str(cfg.stop_time,16));
out=sim(in);
end
