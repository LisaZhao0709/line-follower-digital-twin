function cfg = project_config(overrides)
% Single source of units, geometry, default gains and reproducible initial pose.
if nargin < 1, overrides = struct(); end
cfg.root = fileparts(mfilename('fullpath'));
S = load(fullfile(cfg.root,'data','track_data.mat'));
names = fieldnames(S);
for k = 1:numel(names), cfg.(names{k}) = S.(names{k}); end
cfg.Ts = 0.02;                  % s; sensor, controller and plant share 50 Hz
cfg.wheel_base_m = 0.12;        % lateral wheel separation; assumed, not measured
cfg.body_length_m = 0.16;       % assumed
cfg.body_width_m = 0.10;        % assumed
cfg.sensor_front_m = 0.05;      % assumed forward offset from axle center
cfg.sensor_spacing_m = 0.008;   % assumed; total array width = 0.056 m
cfg.sensor_weights = 3.5:-1:-3.5; % S1 on the LEFT; local y positive left
cfg.km = 0.35;                 % m/s per normalized command; ideal motor model
cfg.base_speed = 0.35;         % normalized; nominal forward speed 0.1225 m/s
cfg.Kp = 0.45;
cfg.Kd = 0.03;                 % seconds, since error and command are normalized
cfg.Ki = 0;                    % reserved for week 5; no integral branch in V4
cfg.derivative_tau = 0.08;     % s; low-pass on discrete derivative
cfg.sensor_threshold = 0.5;
cfg.loss_timeout_s = 0.20;     % short protection used to make tuning repeatable
cfg.stop_time = 100;           % simulation seconds, not wall-clock seconds
cfg.integration_method = 'euler'; % exact_zoh is used by the reviewed Exact models
cfg.results_dir = fullfile(cfg.root,'results');
cfg.models_dir = fullfile(cfg.root,'models');
for folder = {cfg.results_dir, fullfile(cfg.results_dir,'figures'), cfg.models_dir}
    if ~isfolder(folder{1}), mkdir(folder{1}); end
end
names = fieldnames(overrides);
for k = 1:numel(names)
    assert(isfield(cfg,names{k}),'Unknown configuration field: %s',names{k});
    cfg.(names{k}) = overrides.(names{k});
end
assert(cfg.Ts>0 && cfg.wheel_base_m>0 && cfg.km>0);
assert(cfg.sensor_spacing_m>0 && cfg.sensor_front_m>=0);
assert(cfg.Kp>=0 && cfg.Kd>=0 && cfg.derivative_tau>0);
assert(cfg.base_speed>0 && cfg.base_speed<=1);
assert(cfg.Ki==0,'V4 implements P/PD only. Integral action belongs to week 5.');
assert(all(isfinite([cfg.Ts cfg.wheel_base_m cfg.km cfg.base_speed cfg.Kp cfg.Kd ...
    cfg.sensor_front_m cfg.sensor_spacing_m cfg.sensor_threshold cfg.derivative_tau ...
    cfg.loss_timeout_s cfg.stop_time cfg.x0 cfg.y0 cfg.theta0])),'Parameters must be finite.');
assert(cfg.sensor_threshold>0 && cfg.sensor_threshold<=1);
assert(cfg.loss_timeout_s>0 && cfg.stop_time>0);
assert(abs(cfg.meters_per_pixel_x-cfg.meters_per_pixel_y)<1e-12, ...
    'This map reader requires isotropic pixels.');
assert(ismember(cfg.integration_method,{'euler','exact_zoh'}));
end
