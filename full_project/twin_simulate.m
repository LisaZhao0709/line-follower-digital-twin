function [out,cfg]=twin_simulate(overrides)
if nargin<1,overrides=struct();end
cfg=twin_config(overrides);build_twin();model='LineFollowerTwin';
load_system(fullfile(cfg.models_dir,[model '.slx']));
input=Simulink.SimulationInput(model);input=input.setVariable('cfg',cfg,'Workspace',model);
for n={'Kp','Ki','Kd'},input=input.setVariable(n{1},cfg.(n{1}),'Workspace',model);end
input=input.setModelParameter('StopTime',num2str(cfg.stop_time,16));out=sim(input);
end
