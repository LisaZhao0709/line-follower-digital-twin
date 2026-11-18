% show_track_map.m
% Display the track, world axes, initial pose, body outline and eight sensor locations in MATLAB.
% Week 1 check: confirm sensor positions before tuning PID; correct coordinates first.
%
% Run init_line_follower.m with an available track_data.mat before this script.

if ~exist("cfg","var")
    error("Run init_line_follower.m to initialize cfg first.");
end

trackMask = cfg.trackMask;
W = cfg.map_width_m;
H = cfg.map_height_m;

%% 1. Display the map in world coordinates with the origin at lower left.
figure("Name","Track map and initial pose","Color","w");
imagesc([0 W], [0 H], ~trackMask);   % Invert so the black line is displayed dark.
set(gca, "YDir", "normal", "FontSize", 10);
colormap(gca, gray); axis image; hold on;
xlabel("World X [m] (positive right)");
ylabel("World Y [m] (positive up)");
title("Binary track: start, initial pose, body and eight sensors");

% Outline the track in red to inspect mask quality.
contour(linspace(0,W,size(trackMask,2)), linspace(0,H,size(trackMask,1)), ...
    double(trackMask), [0.5 0.5], "r", "LineWidth", 0.5);

%% 2. World axes at the origin.
quiver(0, 0, 0.10*W, 0, 0, "k", "LineWidth", 1.5, "MaxHeadSize", 0.5);
quiver(0, 0, 0, 0.10*H, 0, "k", "LineWidth", 1.5, "MaxHeadSize", 0.5);
text(0.10*W, 0, "  x", "Color","k", "FontWeight","bold");
text(0, 0.10*H, "  y", "Color","k", "FontWeight","bold");

%% 3. Start position and initial heading.
x0 = cfg.x0; y0 = cfg.y0; th = cfg.theta0;
plot(x0, y0, "ko", "MarkerFaceColor","y", "MarkerSize", 8);
arrowLen = 0.15 * max(W,H);
quiver(x0, y0, arrowLen*cos(th), arrowLen*sin(th), 0, ...
    "Color",[0 0.6 0], "LineWidth", 2, "MaxHeadSize", 0.6);
text(x0, y0, "  Start", "Color","k", "FontWeight","bold");

%% 4. Body rectangle: length body_length and width body_width.
L = cfg.body_length_m; Bw = cfg.body_width_m;
bodyLocal = [ L/2  Bw/2;
              L/2 -Bw/2;
             -L/2 -Bw/2;
             -L/2  Bw/2;
              L/2  Bw/2 ]';
R = [cos(th) -sin(th); sin(th) cos(th)];
bodyWorld = R * bodyLocal + [x0; y0];
plot(bodyWorld(1,:), bodyWorld(2,:), "b-", "LineWidth", 1.5);

%% 5. Eight sensor locations.
sf = cfg.sensor_front_m;
syl = cfg.sensor_spacing_m * cfg.sensor_weights;
X = x0 + cos(th)*sf - sin(th)*syl;
Y = y0 + sin(th)*sf + cos(th)*syl;
plot(X, Y, "ro", "MarkerFaceColor","r", "MarkerSize", 5);
for i = 1:numel(X)
    text(X(i), Y(i), " s"+i, "Color",[0.7 0 0], "FontSize", 7);
end

%% 6. Check sampled pixel coordinates for the leftmost sensor.
Hpx = size(trackMask,1);
col = 1 + round(X(1)/cfg.meters_per_pixel_x);
row = Hpx - round(Y(1)/cfg.meters_per_pixel_y);
fprintf("Sensor s1 world coordinates (%.3f, %.3f) m -> pixel (row=%d, col=%d)\n", ...
    X(1), Y(1), row, col);
if row>=1 && row<=Hpx && col>=1 && col<=size(trackMask,2)
    fprintf("Pixel is inside the map; mask = %d (1=line, 0=background).\n", trackMask(row,col));
else
    fprintf("Warning: pixel is outside the map. Check the initial pose and pixel scale.\n");
end

legend("Track outline","","","Start","Initial heading","Body","Eight sensors", ...
    "Location","bestoutside");
hold off;

%% 7. Save the verification screenshot.
drawnow;
exportgraphics(gcf, fullfile(cfg.results_dir, "figures", "week1_coordinate_check.png"), ...
    "Resolution", 150);
fprintf("Saved screenshot: results/figures/week1_coordinate_check.png\n");
