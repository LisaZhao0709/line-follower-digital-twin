function cfg=twin_config(overrides)
% SI units. Geometry and motor factors are assumptions, not hardware calibration.
if nargin<1,overrides=struct();end
cfg.root=fileparts(mfilename('fullpath'));
S=load(fullfile(cfg.root,'data','track_data.mat'));f=fieldnames(S);
for k=1:numel(f),cfg.(f{k})=S.(f{k});end
cfg.Ts=.02;cfg.wheel_base_m=.12;cfg.body_length_m=.16;cfg.body_width_m=.10;
cfg.sensor_front_m=.05;cfg.sensor_spacing_m=.008;cfg.sensor_weights=3.5:-1:-3.5;
cfg.km=.35;cfg.base_speed=.35;cfg.Kp=.45;cfg.Ki=.015;cfg.Kd=.03;
cfg.integral_limit=.20;cfg.anti_windup=true;cfg.derivative_tau=.08;
cfg.sensor_threshold=.5;cfg.loss_timeout_s=.20;cfg.stop_time=100;
cfg.motor_left_factor=1;cfg.motor_right_factor=1;
cfg.dropout_start_s=1000;cfg.dropout_duration_s=0;cfg.sensor_noise=0;
cfg.environment_level=0;cfg.environment_seed=7;
cfg.integration_method='exact_zoh';
cfg.models_dir=fullfile(cfg.root,'models');cfg.results_dir=fullfile(cfg.root,'results');
f=fieldnames(overrides);
for k=1:numel(f)
    assert(isfield(cfg,f{k}),'Twin:UnknownParameter','Unknown parameter %s',f{k});
    cfg.(f{k})=overrides.(f{k});
end
v=[cfg.Ts cfg.wheel_base_m cfg.km cfg.base_speed cfg.Kp cfg.Ki cfg.Kd ...
 cfg.integral_limit cfg.derivative_tau cfg.sensor_threshold cfg.loss_timeout_s ...
 cfg.stop_time cfg.motor_left_factor cfg.motor_right_factor cfg.dropout_start_s ...
 cfg.dropout_duration_s cfg.sensor_noise cfg.sensor_front_m cfg.sensor_spacing_m ...
 cfg.x0 cfg.y0 cfg.theta0];
assert(all(isfinite(v)),'Twin:InvalidParameter','All scalar parameters must be finite.');
validateattributes(cfg.environment_level,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',2});
validateattributes(cfg.environment_seed,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',2^32-1});
assert(cfg.Ts>=.001 && cfg.Ts<=.1 && cfg.wheel_base_m>0 && cfg.km>0);
assert(cfg.base_speed>0 && cfg.base_speed<1 && cfg.stop_time>0 && cfg.stop_time<=300);
assert(cfg.Kp>=0 && cfg.Kp<=20 && cfg.Ki>=0 && cfg.Ki<=2 && cfg.Kd>=0 && cfg.Kd<=.5);
assert(cfg.integral_limit>0 && cfg.derivative_tau>0 && cfg.loss_timeout_s>0);
assert(cfg.sensor_front_m>=0 && cfg.sensor_spacing_m>0 && cfg.sensor_threshold>0 && cfg.sensor_threshold<=1);
assert(cfg.motor_left_factor>0 && cfg.motor_left_factor<=2 && cfg.motor_right_factor>0 && cfg.motor_right_factor<=2);
assert(cfg.dropout_start_s>=0 && cfg.dropout_duration_s>=0 && cfg.sensor_noise>=0 && cfg.sensor_noise<=.3);
assert(isscalar(cfg.anti_windup) && (cfg.anti_windup==0 || cfg.anti_windup==1));
assert(abs(cfg.meters_per_pixel_x-cfg.meters_per_pixel_y)<1e-12);
assert(abs(cfg.stop_time/cfg.Ts-round(cfg.stop_time/cfg.Ts))<1e-8,'Stop time must be an integer number of samples.');
cfg.environment_input=twin_environment(cfg);
end
