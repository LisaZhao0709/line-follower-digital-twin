% preprocess_track.m
% Track photograph -> binary track map.
%   Output track_mask.png (line=1, background=0) and track_data.mat with pixel scale.
%
% Read -> optional crop -> optional perspective correction -> grayscale -> threshold -> denoise -> save.
% Edit the configuration section below before running this script.

clear; clc; close all;

%% ===== Configuration: edit for the actual photograph and track. =====
photoFile    = "photos/track_photo.jpg";  % Source photograph path
map_width_m  = NaN;    % <MEASURE> physical map width [m], required
map_height_m = NaN;    % <MEASURE> physical map height [m], required

doCrop        = false; % Set true to select a crop manually.
doPerspective = false; % Set true for a visibly trapezoidal, oblique photograph.
threshold     = [];    % Empty uses Otsu thresholding; alternatively set a fixed value such as 0.40.
minBlobPx     = 30;    % Remove isolated components smaller than this size; 0 disables removal.

outMask = "track_mask.png";
outMat  = "track_data.mat";
%% ==================================

%% 1. Read the photograph.
assert(isfile(photoFile), "Photograph not found: %s", photoFile);
img = imread(photoFile);
fprintf("Original size: %d(H) x %d(W), channels: %d\n", size(img,1), size(img,2), size(img,3));

%% 2. Convert to grayscale.
if size(img,3) == 3
    gray = im2gray(img);
else
    gray = img;
end
gray = im2double(gray);

%% 3. Optional manual crop.
if doCrop
    figure("Name","Crop: draw a track rectangle and double-click.");
    imshow(gray); title("Select the track area and double-click to confirm.");
    h = drawrectangle;
    wait(h);
    r = round(h.Position);
    gray = gray(r(2):r(2)+r(4), r(1):r(1)+r(3));
    close(gcf);
    fprintf("Cropped size: %d(H) x %d(W)\n", size(gray,1), size(gray,2));
end

%% 4. Optional perspective correction.
if doPerspective
    figure("Name","Perspective correction: select four corners in order.");
    imshow(gray);
    title("Select top-left -> top-right -> bottom-right -> bottom-left.");
    [cx, cy] = ginput(4);
    close(gcf);
    moving = [cx(:) cy(:)];

    % Use the measured aspect ratio when available; otherwise keep the image dimensions.
    if ~isnan(map_width_m) && ~isnan(map_height_m)
        targetW = size(gray,2);
        targetH = round(targetW * map_height_m / map_width_m);
    else
        targetW = size(gray,2);
        targetH = size(gray,1);
    end
    fixed = [1 1; targetW 1; targetW targetH; 1 targetH];

    if exist("fitgeotform2d","file") == 2
        tform = fitgeotform2d(moving, fixed, "projective");
    else
        tform = fitgeotrans(moving, fixed, "projective");
    end
    outView = imref2d([targetH targetW]);
    gray = imwarp(gray, tform, "OutputView", outView);

    figure("Name","Perspective correction result");
    imshow(gray); title("Corrected grayscale image: check that the track is rectangular.");
    drawnow;
    fprintf("Corrected size: %d(H) x %d(W)\n", size(gray,1), size(gray,2));
end

%% 5. Thresholding: black line = 1.
if isempty(threshold)
    T = graythresh(gray);
else
    T = threshold;
end
trackMask = gray < T;
fprintf("Threshold T = %.3f; line pixels: %.2f%%\n", ...
    T, 100*mean(trackMask(:)));

%% 6. Remove isolated noise.
if minBlobPx > 0 && exist("bwareaopen","file") == 2
    before = nnz(trackMask);
    trackMask = bwareaopen(trackMask, minBlobPx);
    fprintf("Denoising removed %d pixels.\n", before - nnz(trackMask));
end

%% 7. Calculate the pixel scale.
assert(~isnan(map_width_m) && ~isnan(map_height_m), ...
    "Enter measured map_width_m and map_height_m first.");
meters_per_pixel_x = map_width_m  / size(trackMask,2);
meters_per_pixel_y = map_height_m / size(trackMask,1);
fprintf("Pixel scale: x=%.6f m/px, y=%.6f m/px\n", ...
    meters_per_pixel_x, meters_per_pixel_y);

%% 8. Display and save the result.
figure("Name","Binary track map");
imshow(trackMask); title("Binary track mask: black line = 1");

imwrite(trackMask, outMask);
save(outMat, "trackMask", "map_width_m", "map_height_m", ...
    "meters_per_pixel_x", "meters_per_pixel_y");

fprintf("Saved: %s, %s\n", outMask, outMat);
fprintf("Completed. Run show_track_map.m to check coordinates and the initial pose.\n");
