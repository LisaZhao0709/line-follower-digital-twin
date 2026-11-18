function [metric,log] = evaluate_run(out,cfg,name)
% Reference boundary is used ONLY here for offline progress, never in feedback.
[t,x]=series_data(out,'x');[~,y]=series_data(out,'y');[~,theta]=series_data(out,'theta');
[~,e]=series_data(out,'error');[~,p]=series_data(out,'P_term');[~,d]=series_data(out,'D_term');
[~,ul]=series_data(out,'uL_log');[~,ur]=series_data(out,'uR_log');
[~,sensors]=series_data(out,'sensors');[~,detected]=series_data(out,'detected');
[~,lost]=series_data(out,'off_track');
assert(all(isfinite([x;y;theta;e;p;d;ul;ur])),'Nonfinite simulation value.');
assert(all(ul>=-1e-12 & ul<=1+1e-12 & ur>=-1e-12 & ur<=1+1e-12));
assert(all(abs(e)<=1+1e-12));
ref=cfg.referenceXY(1:end-1,:);arc=cfg.referenceArc(:);lengthM=arc(end);
ids=1:5:numel(t);progress=zeros(numel(ids),1);nearestDistance=progress;
previous=0;first=true;lapTime=NaN;lapIndex=numel(t);
for k=1:numel(ids)
    i=ids(k);
    [distanceSquared,j]=min((ref(:,1)-x(i)).^2+(ref(:,2)-y(i)).^2);
    nearestDistance(k)=sqrt(distanceSquared);current=arc(j);
    if first,previous=current;first=false;end
    ds=current-previous;
    if ds<-lengthM/2,ds=ds+lengthM;end
    if ds>lengthM/2,ds=ds-lengthM;end
    if k>1,progress(k)=progress(k-1)+ds;end
    previous=current;
    if isnan(lapTime) && progress(k)>=lengthM && hypot(x(i)-cfg.x0,y(i)-cfg.y0)<.08
        lapTime=t(i);lapIndex=i;
    end
end
stopIndex=find(lost>0.5,1);
stopTime=NaN;
if ~isempty(stopIndex)
    stopTime=t(stopIndex);
    if isnan(lapTime),lapIndex=stopIndex;end
end
keep=1:lapIndex;valid=detected(keep)>0.5;
metric.case_name=string(name);metric.Kp=cfg.Kp;metric.Kd=cfg.Kd;
metric.completed_lap=~isnan(lapTime);metric.lap_time_s=lapTime;
metric.stop_time_s=stopTime;metric.analysis_end_s=t(lapIndex);
metric.progress_fraction=max(progress(ids<=lapIndex))/lengthM;
metric.mae_sensor_error=mean(abs(e(keep(valid))));
metric.peak_sensor_error=max(abs(e(keep(valid))));
metric.missing_fraction=mean(~valid);
metric.stopped_off_track=any(lost>0.5);
metric.command_saturation_fraction=mean(ul(keep)<=1e-6 | ul(keep)>=1-1e-6 | ur(keep)<=1e-6 | ur(keep)>=1-1e-6);
metric.command_total_variation=sum(abs(diff(ul(keep)))+abs(diff(ur(keep))));
metric.error_sign_changes=count_crossings(e(keep),.02);
metric.max_distance_to_reference_edge_m=max(nearestDistance(ids<=lapIndex));
log=table(t,x,y,theta,e,p,d,ul,ur,cfg.km*ul,cfg.km*ur,detected,lost, ...
    'VariableNames',{'time_s','x_m','y_m','theta_rad','sensor_error','P_term','D_term', ...
    'uL','uR','sim_vL_mps','sim_vR_mps','line_detected','off_track'});
for k=1:8,log.(sprintf('S%d',k))=sensors(:,k);end
writetable(log,fullfile(cfg.results_dir,[char(name) '_trace.csv']));
save(fullfile(cfg.results_dir,[char(name) '_run.mat']),'out','cfg','metric');
end

function n=count_crossings(e,deadband)
state=0;n=0;
for k=1:numel(e)
    if e(k)>deadband,new=1;elseif e(k)<-deadband,new=-1;else,continue;end
    if state~=0 && new~=state,n=n+1;end
    state=new;
end
end
