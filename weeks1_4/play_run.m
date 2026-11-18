function play_run(out,speed,cfg)
% Animate recorded SIMULATION data; does not pretend to be live hardware.
if nargin<3,cfg=project_config();end
if nargin<1
    S=load(fullfile(cfg.results_dir,'PD_default_run.mat'),'out','cfg');out=S.out;cfg=S.cfg;
end
if nargin<2,speed=5;end
assert(speed>0);
[t,x]=series_data(out,'x');[~,y]=series_data(out,'y');[~,th]=series_data(out,'theta');
[~,binary]=series_data(out,'sensors');[~,sx]=series_data(out,'sensorX');[~,sy]=series_data(out,'sensorY');
[~,e]=series_data(out,'error');[~,ul]=series_data(out,'uL_log');[~,ur]=series_data(out,'uR_log');
fig=figure('Name','Recorded virtual car playback','Color','w','Position',[100 70 1050 760]);
imagesc([0 cfg.map_width_m],[0 cfg.map_height_m],flipud(double(cfg.trackMask)));
set(gca,'YDir','normal');colormap([1 1 1;0 0 0]);axis equal tight;hold on;
trail=plot(NaN,NaN,'Color',[0 .45 .9],'LineWidth',1.2);
body=plot(NaN,NaN,'b-','LineWidth',1.5);
arrow=quiver(x(1),y(1),.10,0,0,'b','LineWidth',1.5);
sensors=plot(sx(1,:),sy(1,:),'ro','MarkerFaceColor',[1 .65 .2],'MarkerSize',5);
local=[.5 .5;.5 -.5;-.5 -.5;-.5 .5;.5 .5].*[cfg.body_length_m cfg.body_width_m];
xlabel('x (m)');ylabel('y (m)');
stride=max(1,round(speed/(25*cfg.Ts)));
for i=1:stride:numel(t)
    if ~isgraphics(fig),break;end
    R=[cos(th(i)) -sin(th(i));sin(th(i)) cos(th(i))];world=local*R.'+[x(i) y(i)];
    set(trail,'XData',x(1:i),'YData',y(1:i));set(body,'XData',world(:,1),'YData',world(:,2));
    set(arrow,'XData',x(i),'YData',y(i),'UData',.10*cos(th(i)),'VData',.10*sin(th(i)));
    set(sensors,'XData',sx(i,:),'YData',sy(i,:));
    title(sprintf('RECORDED SIMULATION | t=%.1f s | e=%+.3f | uL=%.2f, uR=%.2f | S=%s', ...
        t(i),e(i),ul(i),ur(i),sprintf('%d',binary(i,:))));
    drawnow;pause(.04);
end
end
