% init_line_follower.m
% Line-follower digital twin simulator: parameter initialization.
% Collect geometry, simulation, PID and initial-state settings in cfg for repeatable resets.
% Run this script in MATLAB before opening the model or starting a simulation.
%
% Week 1: replace NaN entries marked <MEASURE> with measurements, then run show_track_map.m.

clear; clc;

%% 1. Map and geometry parameters: enter Week 1 measurements.
cfg.acquire_date     = "";        % Example: "2026-09-23"

% --- Track measurements ---
cfg.map_width_m      = NaN;       % <MEASURE> physical map width [m]
cfg.map_height_m     = NaN;       % <MEASURE> physical map height [m]
cfg.line_width_m     = NaN;       % <MEASURE> black line width [m]

% --- Vehicle measurements ---
cfg.wheel_base_m     = NaN;       % <MEASURE> wheel separation L [m]
cfg.body_length_m    = NaN;       % <MEASURE> body length [m]
cfg.body_width_m     = NaN;       % <MEASURE> body width [m]
cfg.sensor_front_m   = NaN;       % <MEASURE> forward offset from body centre to sensor array [m]
cfg.sensor_spacing_m = NaN;       % <MEASURE> adjacent sensor spacing [m]

% --- Eight sensor weights, left to right; keep fixed.---
cfg.sensor_weights   = [-3.5 -2.5 -1.5 -0.5 0.5 1.5 2.5 3.5];
cfg.error_scale      = 3.5;       % Error-normalization denominator

% --- Pixel scale: populated by preprocess_track.m; do not enter manually. ---
cfg.meters_per_pixel_x = NaN;
cfg.meters_per_pixel_y = NaN;

%% 2. Simulation and control parameters: instructor settings.
cfg.Ts                = 0.02;     % Fixed time step [s]
cfg.base_speed        = 0.35;     % Base speed: normalized command in [0,1]
cfg.max_command       = 1.0;      % Command upper bound
cfg.integral_limit    = 0.30;     % Integral limit
cfg.derivative_filter = 20;       % Derivative filter coefficient N

% --- Default PID: students change only these three gains. ---
cfg.Kp = 0.80;
cfg.Ki = 0.00;
cfg.Kd = 0.08;

%% 3. Initial pose: origin at the lower-left map corner; x right, y up, theta counterclockwise.
cfg.x0     = NaN;                 % <SET> initial x [m]
cfg.y0     = NaN;                 % <SET> initial y [m]
cfg.theta0 = 0.0;                 % <SET> initial heading [rad]

%% 4. Data logging
cfg.enable_logging = true;
cfg.map_file       = "track_data.mat";
cfg.results_dir    = "results";

%% 5. Load map data if available.
if isfile(cfg.map_file)
    S = load(cfg.map_file);
    cfg.trackMask          = S.trackMask;
    cfg.map_width_m        = S.map_width_m;
    cfg.map_height_m       = S.map_height_m;
    cfg.meters_per_pixel_x = S.meters_per_pixel_x;
    cfg.meters_per_pixel_y = S.meters_per_pixel_y;
    fprintf("Loaded map %s: %d x %d px, %.3f x %.3f m\n", ...
        cfg.map_file, size(cfg.trackMask,1), size(cfg.trackMask,2), ...
        cfg.map_width_m, cfg.map_height_m);
else
    warning("Cannot find %s. Run preprocess_track.m first.", cfg.map_file);
end

%% 6. Completeness check
missing = {};
fields = ["map_width_m","map_height_m","line_width_m","wheel_base_m", ...
          "body_length_m","body_width_m","sensor_front_m","sensor_spacing_m", ...
          "x0","y0"];
for f = fields
    if isnan(cfg.(f))
        missing{end+1} = f; %#ok<SAGROW>
    end
end
if isempty(missing)
    fprintf("Parameter check passed.\n");
else
    warning("The following parameters are NaN; enter measured values: %s", strjoin(missing, ", "));
end

fprintf("init_line_follower.m completed.PID: Kp=%.2f Ki=%.2f Kd=%.2f, Ts=%.3f s\n", ...
    cfg.Kp, cfg.Ki, cfg.Kd, cfg.Ts);
