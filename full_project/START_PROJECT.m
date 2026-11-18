% One command opens the complete classroom interface with a verified experiment.
root=fileparts(mfilename('fullpath'));addpath(root,fullfile(root,'kernels'));
build_twin();lineFollowerApp=twin_app();
fprintf('The project dashboard is open. Edit Kp/Ki/Kd and select New experiment; results are saved automatically.\n');
