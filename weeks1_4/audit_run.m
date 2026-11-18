function record=audit_run(out,cfg,name,model,directory)
% Export raw signals and independently verify all sensor/control/state recurrences.
names={'x','y','theta','strength','sensors','sensorX','sensorY','error','P_term','D_term','uL_log','uR_log','detected','off_track'};
[t,x]=series_data(out,'x');data=struct();
for k=1:numel(names)
    [tt,values]=series_data(out,names{k});
    assert(isequal(tt,t),'Signal timestamps disagree: %s',names{k});
    assert(all(isfinite(values),'all'),'Nonfinite signal: %s',names{k});
    data.(names{k})=values;
end
assert(abs(t(1))<1e-12 && max(abs(diff(t)-cfg.Ts))<1e-10);
assert(abs(t(end)-cfg.stop_time)<1e-10);
assert(max(abs([x(1)-cfg.x0,data.y(1)-cfg.y0,data.theta(1)-cfg.theta0]))<1e-12);
assert(all(data.uL_log>=0 & data.uL_log<=1 & data.uR_log>=0 & data.uR_log<=1));
assert(all(data.sensors==0 | data.sensors==1,'all'));
N=numel(t);local=(3.5:-1:-3.5)*cfg.sensor_spacing_m;
X=x+cos(data.theta)*cfg.sensor_front_m-sin(data.theta)*local;
Y=data.y+sin(data.theta)*cfg.sensor_front_m+cos(data.theta)*local;
% interp2 is a separate implementation from the embedded four-pixel sampler.
strength=interp2(cfg.trackReflectance,1+X/cfg.meters_per_pixel_x, ...
    size(cfg.trackReflectance,1)-Y/cfg.meters_per_pixel_y,'linear',0);
binary=double(strength>=cfg.sensor_threshold);
detected=double(any(binary>0,2));
raw=(strength*(3.5:-1:-3.5).')./(3.5*max(sum(strength,2),1e-12));
held=zeros(N,1);filtered=zeros(N,1);off=zeros(N,1);lossStart=NaN;stopped=false;
alpha=cfg.Ts/(cfg.derivative_tau+cfg.Ts);previousError=0;previousD=0;
for i=1:N
    if detected(i)
        held(i)=raw(i);lossStart=NaN;
    else
        held(i)=previousError;if isnan(lossStart),lossStart=t(i);end
    end
    filtered(i)=alpha*(held(i)-previousError)/cfg.Ts+(1-alpha)*previousD;
    if ~isnan(lossStart) && t(i)-lossStart>=cfg.loss_timeout_s-1e-12,stopped=true;end
    off(i)=double(stopped);previousError=held(i);previousD=filtered(i);
end
p=cfg.Kp*held;d=cfg.Kd*filtered;correction=p+d;
expectedL=min(max(cfg.base_speed-correction,0),1).*(1-off);
expectedR=min(max(cfg.base_speed+correction,0),1).*(1-off);
v=cfg.km*(data.uL_log+data.uR_log)/2;
w=cfg.km*(data.uR_log-data.uL_log)/cfg.wheel_base_m;
if strcmp(cfg.integration_method,'exact_zoh')
    h=w(1:end-1)*cfg.Ts/2;factor=ones(size(h));nz=abs(h)>1e-10;factor(nz)=sin(h(nz))./h(nz);
    dx=cfg.Ts*v(1:end-1).*factor.*cos(data.theta(1:end-1)+h);
    dy=cfg.Ts*v(1:end-1).*factor.*sin(data.theta(1:end-1)+h);
else
    dx=cfg.Ts*v(1:end-1).*cos(data.theta(1:end-1));
    dy=cfg.Ts*v(1:end-1).*sin(data.theta(1:end-1));
end
errors=[max(abs(strength-data.strength),[],'all');max(abs(X-data.sensorX),[],'all'); ...
    max(abs(Y-data.sensorY),[],'all');max(abs(binary-data.sensors),[],'all'); ...
    max(abs(detected-data.detected));max(abs(held-data.error));max(abs(p-data.P_term)); ...
    max(abs(d-data.D_term));max(abs(off-data.off_track)); ...
    max(abs(expectedL-data.uL_log));max(abs(expectedR-data.uR_log)); ...
    max(abs(diff(x)-dx));max(abs(diff(data.y)-dy));max(abs(diff(data.theta)-cfg.Ts*w(1:end-1)))];
labels={'sensor_interpolation','sensor_X','sensor_Y','sensor_binary','line_detected', ...
    'held_error','P_term','D_term','loss_guard','left_command','right_command','X_update','Y_update','theta_update'};
checks=table(string(labels.'),errors,repmat(1e-9,14,1),errors<1e-9, ...
    'VariableNames',{'check','max_absolute_difference','tolerance','passed'});
assert(all(checks.passed),'Logged values failed equation-level verification.');
writetable(checks,fullfile(directory,[name '_equation_checks.csv']));
lap=lap_review(t,x,data.y,cfg);
stopIndex=find(data.off_track>.5,1);stopTime=NaN;
if lap.completed_lap,endIndex=lap.finish_sample_index;else,endIndex=N;end
if ~isempty(stopIndex)
    stopTime=t(stopIndex);if ~lap.completed_lap,endIndex=stopIndex;end
end
keep=1:endIndex;valid=data.detected(keep)>0;
record.case_name=string(name);record.model=string(model);record.integration=string(cfg.integration_method);
record.Ts_s=cfg.Ts;record.Kp=cfg.Kp;record.Kd=cfg.Kd;
record.completed_lap=lap.completed_lap;record.lap_time_s=lap.lap_time_s;
record.stop_time_s=stopTime;record.analysis_end_s=t(endIndex);
record.route_sector_fraction=lap.route_sector_fraction;
if any(valid)
    record.mae_sensor_error=mean(abs(data.error(keep(valid))));
    record.rms_sensor_error=sqrt(mean(data.error(keep(valid)).^2));
    record.peak_sensor_error=max(abs(data.error(keep(valid))));
else
    record.mae_sensor_error=NaN;record.rms_sensor_error=NaN;record.peak_sensor_error=NaN;
end
record.missing_fraction=mean(~valid);record.stopped_off_track=any(data.off_track>.5);
record.command_saturation_fraction=mean(data.uL_log(keep)<=1e-6 | data.uL_log(keep)>=1-1e-6 | ...
    data.uR_log(keep)<=1e-6 | data.uR_log(keep)>=1-1e-6);
record.command_total_variation=sum(abs(diff(data.uL_log(keep)))+abs(diff(data.uR_log(keep))));
record.max_equation_residual=max(errors);
record.lap_timing_bracket_s=cfg.Ts;
log=table(t,x,data.y,data.theta,data.error,p,d,data.uL_log,data.uR_log,detected,off, ...
    lap.progress_fraction,lap.reference_edge_distance, ...
    'VariableNames',{'time_s','x_m','y_m','theta_rad','sensor_error','P_term','D_term','uL','uR', ...
    'line_detected','off_track','reference_edge_progress','distance_to_reference_edge_m'});
for k=1:8
    log.(sprintf('S%d',k))=data.sensors(:,k);log.(sprintf('strength%d',k))=data.strength(:,k);
    log.(sprintf('sensorX%d_m',k))=data.sensorX(:,k);log.(sprintf('sensorY%d_m',k))=data.sensorY(:,k);
end
writetable(log,fullfile(directory,[name '_trace.csv']));
save(fullfile(directory,[name '_run.mat']),'out','cfg','record','lap','checks');
metadata=rmfield(cfg,{'trackMask','trackReflectance','referenceXY','referenceArc'});
metadata.model=model;metadata.case_name=name;
metadata.executed_at=char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyy-MM-dd HH:mm:ss Z'));
fid=fopen(fullfile(directory,[name '_parameters.json']),'w','n','UTF-8');assert(fid>=0);
fprintf(fid,'%s',jsonencode(metadata,'PrettyPrint',true));fclose(fid);
fprintf('AUDIT %s: lap=%d time=%.6f residual=%.3g\n',name,record.completed_lap,record.lap_time_s,max(errors));
end
