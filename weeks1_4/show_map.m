function fig = show_map(cfg)
if nargin<1,cfg=project_config();end
addpath(fullfile(cfg.root,'kernels'));
fig=figure('Name','Week 1: map and coordinates','Color','w','Position',[80 80 1300 650]);
tiledlayout(1,2,'TileSpacing','compact');nexttile;
imagesc([0 cfg.map_width_m],[0 cfg.map_height_m],flipud(double(cfg.trackMask)));
set(gca,'YDir','normal');colormap([1 1 1;0 0 0]);axis equal tight;hold on;
xlabel('World x (m)');ylabel('World y (m)');
title(sprintf('Retained inner loop / line width 0.02 m / estimated %.2f x %.2f m',cfg.map_width_m,cfg.map_height_m));
body=[.5 .5; .5 -.5; -.5 -.5; -.5 .5; .5 .5].*[cfg.body_length_m cfg.body_width_m];
R=[cos(cfg.theta0) -sin(cfg.theta0);sin(cfg.theta0) cos(cfg.theta0)];
world=body*R.'+[cfg.x0 cfg.y0];
plot(world(:,1),world(:,2),'b-','LineWidth',1.5);
plot(cfg.x0,cfg.y0,'bo','MarkerFaceColor','y');
quiver(cfg.x0,cfg.y0,.15*cos(cfg.theta0),.15*sin(cfg.theta0),0,'b','LineWidth',1.5);
[~,binary,X,Y]=virtual_sensors(cfg.x0,cfg.y0,cfg.theta0,cfg.trackReflectance, ...
    cfg.meters_per_pixel_x,cfg.sensor_front_m,cfg.sensor_spacing_m,cfg.sensor_threshold);
scatter(X,Y,38,binary,'filled','MarkerEdgeColor',[.8 0 0]);
text(.04,cfg.map_height_m-.06,'Origin: lower left. x right, y up, theta CCW.','FontSize',10);
nexttile;
imagesc([0 cfg.map_width_m],[0 cfg.map_height_m],flipud(double(cfg.trackMask)));
set(gca,'YDir','normal');colormap(gca,[1 1 1;0 0 0]);hold on;axis equal;
plot(world(:,1),world(:,2),'b-','LineWidth',1.5);
plot(cfg.x0,cfg.y0,'bo','MarkerFaceColor','y');
quiver(cfg.x0,cfg.y0,.08*cos(cfg.theta0),.08*sin(cfg.theta0),0,'b','LineWidth',1.5);
plot(X,Y,'ro','MarkerFaceColor',[1 .7 .3],'MarkerSize',7);
for k=1:8,text(X(k)+.012,Y(k),sprintf('S%d = %d',k,binary(k)),'FontSize',10,'Color',[.7 0 0]);end
xlim([cfg.x0-.11 cfg.x0+.16]);ylim([cfg.y0-.10 cfg.y0+.10]);
xlabel('x (m)');ylabel('y (m)');title('Start zoom: S1 left, S8 right');
exportgraphics(fig,fullfile(cfg.results_dir,'figures','week1_map_coordinates.png'),'Resolution',150);
end
