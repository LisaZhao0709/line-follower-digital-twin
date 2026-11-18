function [record,trace]=twin_record(out,cfg,name,directory)
% Full frozen trace, independent MATLAB equations, and conservative finish gate.
if ~isfolder(directory),mkdir(directory);end
signals={'x','y','theta','strength','sensors','sensorX','sensorY','error','P_term','I_term','D_term', ...
 'correction','anti_windup','uL_log','uR_log','detected','off_track','stop_reason','enabled', ...
 'left_speed','right_speed','expected_left_speed','expected_right_speed','left_residual','right_residual'};
[t,~]=series_data(out,'x');d=struct();
for k=1:numel(signals)
    [tt,z]=series_data(out,signals{k});assert(isequal(t,tt));assert(all(isfinite(z),'all'));d.(signals{k})=z;
end
N=numel(t);sx=d.x+cos(d.theta)*cfg.sensor_front_m-sin(d.theta)*(3.5:-1:-3.5)*cfg.sensor_spacing_m;
sy=d.y+sin(d.theta)*cfg.sensor_front_m+cos(d.theta)*(3.5:-1:-3.5)*cfg.sensor_spacing_m;
ideal=interp2(cfg.trackReflectance,1+sx/cfg.meters_per_pixel_x,size(cfg.trackReflectance,1)-sy/cfg.meters_per_pixel_y,'linear',0);
environment=twin_environment(cfg);assert(numel(t)==size(environment,1) && max(abs(t-environment(:,1)))<1e-9);
environment=environment(:,2:end);
sx=sx+cos(d.theta).*environment(:,3)-sin(d.theta).*environment(:,4);
sy=sy+sin(d.theta).*environment(:,3)+cos(d.theta).*environment(:,4);
clean=interp2(cfg.trackReflectance,1+sx/cfg.meters_per_pixel_x,size(cfg.trackReflectance,1)-sy/cfg.meters_per_pixel_y,'linear',0);
strength=min(max(environment(:,1).*clean+environment(:,2)+environment(:,5:12) ...
    +cfg.sensor_noise*sin(2*pi*t*(8:15)+.37*(1:8)),0),1);
strength(t>=cfg.dropout_start_s-1e-12 & t<cfg.dropout_start_s+cfg.dropout_duration_s-1e-12,:)=0;
binary=double(strength>=cfg.sensor_threshold);detected=double(any(binary,2));
raw=strength*(3.5:-1:-3.5).'./(3.5*max(sum(strength,2),1e-12));
e=zeros(N,1);derivative=e;I=e;blocked=e;reason=e;start=NaN;last=0;lastD=0;state=0;code=0;
a=cfg.Ts/(cfg.derivative_tau+cfg.Ts);
for i=1:N
    if detected(i),e(i)=raw(i);start=NaN;else,e(i)=last;if isnan(start),start=t(i);end,end
    derivative(i)=a*(e(i)-last)/cfg.Ts+(1-a)*lastD;
    P=cfg.Kp*e(i);D=cfg.Kd*derivative(i);
    if cfg.Ki==0,state=0;elseif detected(i)
        delta=cfg.Ki*e(i)*cfg.Ts;candidate=min(max(state+delta,-cfg.integral_limit),cfg.integral_limit);
        total=P+D+candidate;
        if cfg.anti_windup && abs(total)>min(cfg.base_speed,1-cfg.base_speed) && total*delta>0,blocked(i)=1;else,state=candidate;end
    end
    I(i)=state;
    if code==0
        if ~all(isfinite([d.x(i),d.y(i),d.theta(i)])),code=3;
        elseif d.x(i)<0 || d.y(i)<0 || d.x(i)>cfg.map_width_m || d.y(i)>cfg.map_height_m,code=2;
        elseif ~isnan(start) && t(i)-start>=cfg.loss_timeout_s-1e-12,code=1;
        elseif t(i)>=cfg.stop_time-1e-12,code=4;end
    end
    reason(i)=code;last=e(i);lastD=derivative(i);
end
P=cfg.Kp*e;D=cfg.Kd*derivative;c=P+I+D;
uL=min(max(cfg.base_speed-c,0),1).*(reason==0);uR=min(max(cfg.base_speed+c,0),1).*(reason==0);
v=(d.left_speed+d.right_speed)/2;omega=(d.right_speed-d.left_speed)/cfg.wheel_base_m;
h=omega(1:end-1)*cfg.Ts/2;factor=ones(size(h));nz=abs(h)>1e-10;factor(nz)=sin(h(nz))./h(nz);
dx=cfg.Ts*v(1:end-1).*factor.*cos(d.theta(1:end-1)+h);dy=cfg.Ts*v(1:end-1).*factor.*sin(d.theta(1:end-1)+h);
labels={'sample_time','sensor_X','sensor_Y','sensor_strength','sensor_binary','detected','held_error','P','I','D','anti_windup','correction','stop_reason','enabled','left_command','right_command', ...
 'left_speed','right_speed','expected_left','expected_right','left_residual','right_residual','X_update','Y_update','theta_update'};
values={diff(t)-cfg.Ts,sx-d.sensorX,sy-d.sensorY,strength-d.strength,binary-d.sensors,detected-d.detected,e-d.error,P-d.P_term,I-d.I_term,D-d.D_term,blocked-d.anti_windup,c-d.correction,reason-d.stop_reason,double(reason==0)-d.enabled, ...
 uL-d.uL_log,uR-d.uR_log,cfg.km*cfg.motor_left_factor*d.uL_log-d.left_speed,cfg.km*cfg.motor_right_factor*d.uR_log-d.right_speed, ...
 cfg.km*d.uL_log-d.expected_left_speed,cfg.km*d.uR_log-d.expected_right_speed,d.left_speed-d.expected_left_speed-d.left_residual,d.right_speed-d.expected_right_speed-d.right_residual, ...
 diff(d.x)-dx,diff(d.y)-dy,diff(d.theta)-cfg.Ts*omega(1:end-1)};
noisy=isfield(cfg,'environment_level') && cfg.environment_level>0;
if noisy
    [~,loggedEnvironment]=series_data(out,'environment');[~,loggedIdeal]=series_data(out,'ideal_strength');
    labels=[labels {'seeded_environment','ideal_strength'}];
    values=[values {environment-loggedEnvironment,ideal-loggedIdeal}];
end
res=zeros(numel(values),1);for k=1:numel(values),res(k)=max(abs(values{k}),[],'all');end
checks=table(string(labels.'),res,res<1e-9,'VariableNames',{'check','max_absolute_difference','passed'});assert(all(checks.passed),'Twin:EquationFailure','Equation verification failed: %s',name);
assert(max(abs(I))<=cfg.integral_limit+1e-12);assert(all(d.uL_log>=0 & d.uL_log<=1 & d.uR_log>=0 & d.uR_log<=1));
lap=twin_lap(t,d.x,d.y,cfg);endIndex=N;if lap.completed_lap,endIndex=lap.finish_sample_index;end
stop=find(reason>0,1);if ~isempty(stop),endIndex=min(endIndex,stop);end
valid=detected(1:endIndex)>0;ev=e(1:endIndex);validError=ev(valid);
record.case_name=string(name);record.Kp=cfg.Kp;record.Ki=cfg.Ki;record.Kd=cfg.Kd;record.Ts_s=cfg.Ts;
record.completed_lap=lap.completed_lap;record.lap_time_s=lap.lap_time_s;record.analysis_end_s=t(endIndex);
record.stop_time_s=NaN;record.stop_reason=0;if ~isempty(stop),record.stop_time_s=t(stop);record.stop_reason=reason(stop);end
record.mae=NaN;record.rms=NaN;record.peak=NaN;if ~isempty(validError),record.mae=mean(abs(validError));record.rms=sqrt(mean(validError.^2));record.peak=max(abs(validError));end
active=d.enabled(1:endIndex)>0;
saturated=d.uL_log(1:endIndex)<=1e-6 | d.uR_log(1:endIndex)<=1e-6 | d.uL_log(1:endIndex)>=1-1e-6 | d.uR_log(1:endIndex)>=1-1e-6;
record.saturation_fraction=NaN;if any(active),record.saturation_fraction=mean(saturated(active));end
record.max_abs_I=max(abs(I(1:endIndex)));record.anti_windup_fraction=mean(blocked(1:endIndex));
record.command_variation=sum(abs(diff(d.uL_log(1:endIndex)))+abs(diff(d.uR_log(1:endIndex))));
record.max_speed_residual=max(abs([d.left_residual(1:endIndex);d.right_residual(1:endIndex)]));
record.route_sector_fraction=lap.route_sector_fraction;record.max_equation_residual=max(res);record.analysis_end_index=endIndex;
record.sensor_strength_rmse=sqrt(mean((d.strength(1:endIndex,:)-ideal(1:endIndex,:)).^2,'all'));
record.sensor_bit_error_fraction=mean(d.sensors(1:endIndex,:)~=(ideal(1:endIndex,:)>=cfg.sensor_threshold),'all');
trace=table(t,d.x,d.y,d.theta,e,P,I,D,c,blocked,d.uL_log,d.uR_log,detected,d.off_track,reason,d.enabled, ...
 d.left_speed,d.right_speed,d.expected_left_speed,d.expected_right_speed,d.left_residual,d.right_residual,lap.progress_fraction,lap.reference_edge_distance, ...
 'VariableNames',{'time_s','x_m','y_m','theta_rad','sensor_error','P_term','I_term','D_term','correction','anti_windup','uL','uR','line_detected','off_track','stop_reason','enabled', ...
 'left_speed_mps','right_speed_mps','expected_left_mps','expected_right_mps','left_residual_mps','right_residual_mps','reference_edge_progress','distance_to_reference_edge_m'});
for k=1:8,trace.(sprintf('S%d',k))=d.sensors(:,k);trace.(sprintf('strength%d',k))=d.strength(:,k);trace.(sprintf('sensorX%d_m',k))=d.sensorX(:,k);trace.(sprintf('sensorY%d_m',k))=d.sensorY(:,k);end
if noisy
    trace.env_light_gain=environment(:,1);trace.env_shadow_bias=environment(:,2);
    trace.env_forward_jitter_m=environment(:,3);trace.env_lateral_jitter_m=environment(:,4);
    for k=1:8
        trace.(sprintf('ideal_strength%d',k))=ideal(:,k);
        trace.(sprintf('sampled_strength%d',k))=clean(:,k);
        trace.(sprintf('env_read_error%d',k))=environment(:,k+4);
    end
end
writetable(trace,fullfile(directory,[name '_trace.csv']));writetable(checks,fullfile(directory,[name '_checks.csv']));
save(fullfile(directory,[name '_run.mat']),'out','cfg','record','lap','checks');
p=rmfield(cfg,{'trackMask','trackReflectance','referenceXY','referenceArc'});p.case_name=name;
if isfield(p,'environment_input'),p=rmfield(p,'environment_input');end
p.executed_at=char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyy-MM-dd HH:mm:ss Z'));
parameterFile=fullfile(directory,[name '_parameters.json']);
if isfile(parameterFile)
    original=jsondecode(fileread(parameterFile));p.executed_at=original.executed_at;
    p.reviewed_at=char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyy-MM-dd HH:mm:ss Z'));
end
twin_write_json(parameterFile,p);
fprintf('CHECKED %s lap=%d time=%.6f stop=%.3f reason=%d MAE=%.5f residual=%.3g\n',name,record.completed_lap,record.lap_time_s,record.stop_time_s,record.stop_reason,record.mae,max(res));
end
