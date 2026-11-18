function summary = week3_sensor_tests()
% Image sampling/sign/index/bounds checks, independent of the controller.
cfg=project_config();addpath(fullfile(cfg.root,'kernels'));
names={'centered','car_above_line','car_below_line','outside_map'};
poses=[cfg.x0 cfg.y0 0; cfg.x0 cfg.y0+.02 0; cfg.x0 cfg.y0-.02 0; -1 -1 0];
rows=cell(4,6);fig=figure('Name','Week 3: eight sensor checks','Color','w');
tiledlayout(4,1);
for k=1:4
    [strength,binary,X,Y]=virtual_sensors(poses(k,1),poses(k,2),poses(k,3), ...
        cfg.trackReflectance,cfg.meters_per_pixel_x,cfg.sensor_front_m,cfg.sensor_spacing_m,cfg.sensor_threshold);
    [e,detected]=line_error(strength,binary);
    assert(all(strength>=0 & strength<=1) && all(binary==0 | binary==1));
    if k==1,assert(detected && abs(e)<.1);end
    if k==2,assert(detected && e<0);end % line is on the car's RIGHT
    if k==3,assert(detected && e>0);end % line is on the car's LEFT
    if k==4,assert(~detected && all(binary==0) && e==0);end
    assert(Y(1)>Y(8) && all(abs(X-X(1))<1e-12));
    nexttile;bar(1:8,strength);ylim([0 1.1]);xticks(1:8);grid on;
    title(sprintf('%s: e=%+.3f, detected=%d',strrep(names{k},'_',' '),e,detected));
    rows(k,:)={names{k},poses(k,1),poses(k,2),e,detected,true};
    fprintf('Week3 %-16s PASS error=%+.4f\n',names{k},e);
end
% Check the actual rotation convention: at pi/2 the sensor row lies ahead in +y.
[~,~,X,Y]=virtual_sensors(cfg.x0,cfg.y0,pi/2,cfg.trackReflectance, ...
    cfg.meters_per_pixel_x,cfg.sensor_front_m,cfg.sensor_spacing_m,cfg.sensor_threshold);
assert(X(1)<X(8) && all(abs(Y-(cfg.y0+cfg.sensor_front_m))<1e-12));
summary=cell2table(rows,'VariableNames',{'case_name','x_m','y_m','error','detected','passed'});
writetable(summary,fullfile(cfg.results_dir,'week3_sensor_tests.csv'));
exportgraphics(fig,fullfile(cfg.results_dir,'figures','week3_sensor_tests.png'),'Resolution',150);
end
