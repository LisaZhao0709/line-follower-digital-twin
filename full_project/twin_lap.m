function result=twin_lap(t,x,y,cfg)
% Offline acceptance: visit all 24 route sectors and cross the finish gate forward.
% The inner track edge is a route reference only, never a physical centerline.
ref=cfg.referenceXY(1:end-1,:);arc=cfg.referenceArc(:);L=arc(end);
N=numel(t);s=zeros(N,1);distance=zeros(N,1);progress=zeros(N,1);
visited=false(1,24);coverage=zeros(N,1);rejectedJumps=0;
for i=1:N
    [d,j]=min((ref(:,1)-x(i)).^2+(ref(:,2)-y(i)).^2);
    distance(i)=sqrt(d);s(i)=arc(j);
    if i==1,start=s(i);else
        ds=s(i)-s(i-1);if ds<-L/2,ds=ds+L;elseif ds>L/2,ds=ds-L;end
        % Arc projection can change abruptly at a corner. A large spatial jump
        % is forbidden, rather than assuming all projected arc changes are motion.
        actualStep=hypot(x(i)-x(i-1),y(i)-y(i-1));
        if actualStep>cfg.km*max(cfg.motor_left_factor,cfg.motor_right_factor)*(t(i)-t(i-1))+1e-8
            rejectedJumps=rejectedJumps+1;ds=0;
        end
        progress(i)=progress(i-1)+ds;
    end
    if distance(i)<=cfg.sensor_front_m+4*cfg.sensor_spacing_m
        sector=min(24,1+floor(mod(s(i)-start,L)/L*24));visited(sector)=true;
    end
    coverage(i)=mean(visited);
end
heading=[cos(cfg.theta0) sin(cfg.theta0)];left=[-heading(2) heading(1)];
along=(x-cfg.x0)*heading(1)+(y-cfg.y0)*heading(2);
normal=(x-cfg.x0)*left(1)+(y-cfg.y0)*left(2);
crossings=find(along(1:end-1)<0 & along(2:end)>=0);
finish=NaN;upperIndex=N;
for k=1:numel(crossings)
    i=crossings(k);
    if coverage(i+1)==1 && progress(i+1)>.95*L && abs(normal(i+1))<=.04 && rejectedJumps==0
        alpha=-along(i)/(along(i+1)-along(i));
        finish=t(i)+alpha*(t(i+1)-t(i));upperIndex=i+1;break;
    end
end
result.completed_lap=~isnan(finish);result.lap_time_s=finish;
result.finish_sample_index=upperIndex;
result.route_sector_fraction=coverage(upperIndex);
result.rejected_spatial_jumps=rejectedJumps;
result.reference_edge_length_m=L;
result.reference_edge_distance=distance;
result.progress_fraction=progress/L;
result.lap_timing_bracket_s=cfg.Ts; % interpolation refines display, not guaranteed hardware precision
end

