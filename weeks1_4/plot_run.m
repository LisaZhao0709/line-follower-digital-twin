function fig=plot_run(out,cfg,name,metric)
if nargin<4,[metric,~]=evaluate_run(out,cfg,name);end
[t,x]=series_data(out,'x');[~,y]=series_data(out,'y');
[~,e]=series_data(out,'error');[~,p]=series_data(out,'P_term');[~,d]=series_data(out,'D_term');
[~,ul]=series_data(out,'uL_log');[~,ur]=series_data(out,'uR_log');
[~,binary]=series_data(out,'sensors');
if metric.completed_lap
    keep=t<=metric.lap_time_s;
elseif isfield(metric,'stop_time_s') && ~isnan(metric.stop_time_s)
    keep=t<=metric.stop_time_s+.5;
else
    keep=true(size(t));
end
fig=figure('Name',['Week 4: ' char(name)],'Color','w','Position',[70 60 1250 850]);
tiledlayout(2,2,'TileSpacing','compact');
nexttile;
imagesc([0 cfg.map_width_m],[0 cfg.map_height_m],flipud(double(cfg.trackMask)));
set(gca,'YDir','normal');colormap(gca,[1 1 1;0 0 0]);axis equal tight;hold on;
plot(x(keep),y(keep),'Color',[0 .45 .9],'LineWidth',1.3);
plot(cfg.x0,cfg.y0,'go','MarkerFaceColor','g');
last=find(keep,1,'last');plot(x(last),y(last),'ro','MarkerFaceColor','r');
xlabel('x (m)');ylabel('y (m)');
title(sprintf('%s: Kp=%.3f, Kd=%.3f / lap=%d',strrep(char(name),'_',' '),cfg.Kp,cfg.Kd,metric.completed_lap));
nexttile;plot(t(keep),[e(keep) p(keep) d(keep)]);grid on;
xlabel('time (s)');ylabel('normalized');legend('sensor error','P','D','Location','best');
title('Control contributions');
nexttile;plot(t(keep),[ul(keep) ur(keep)]);ylim([-.05 1.05]);grid on;
xlabel('time (s)');ylabel('command [0,1]');legend('left','right');
title('Normalized motor commands');
nexttile;imagesc(t(keep),1:8,binary(keep,:).');set(gca,'YDir','reverse');
colormap(gca,[1 1 1;0 .45 .9]);xlabel('time (s)');ylabel('sensor index (left to right)');
title('Eight virtual sensor outputs');
exportgraphics(fig,fullfile(cfg.results_dir,'figures',[char(name) '.png']),'Resolution',150);
end
