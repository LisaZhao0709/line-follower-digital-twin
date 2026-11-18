root=fileparts(mfilename('fullpath'));addpath(root,fullfile(root,'kernels'));build_twin();
cfg=twin_config();model='LineFollowerTwin';load_system(fullfile(cfg.models_dir,[model '.slx']));
mw=get_param(model,'ModelWorkspace');assignin(mw,'cfg',cfg);
for n={'Kp','Ki','Kd'},assignin(mw,n{1},cfg.(n{1}));end
open_system(model);
