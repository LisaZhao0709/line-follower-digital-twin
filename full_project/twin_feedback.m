function feedback=twin_feedback(trace,cfg)
% Causal one-second windows. Heuristics describe behavior, not prove gain optimality.
t=trace.time_s;N=numel(t);W=max(2,round(1/cfg.Ts));valid=trace.line_detected>0;
count=movsum(double(valid),[W-1 0]);den=max(count,1);
mae=movsum(abs(trace.sensor_error).*valid,[W-1 0])./den;
rmsE=sqrt(movsum(trace.sensor_error.^2.*valid,[W-1 0])./den);
mae(count==0)=NaN;rmsE(count==0)=NaN;
cross=zeros(N,1);last=0;
for k=1:N
    if ~valid(k),last=0;continue;end
    if trace.sensor_error(k)>.045,s=1;elseif trace.sensor_error(k)<-.045,s=-1;else,s=0;end
    if s~=0,if last~=0 && last~=s,cross(k)=1;end;last=s;end
end
duration=min(t,1);zcr=movsum(cross,[W-1 0])./max(duration,cfg.Ts);
active=trace.enabled>0;
sat=(trace.uL<=1e-6 | trace.uR<=1e-6 | trace.uL>=1-1e-6 | trace.uR>=1-1e-6) & active;
satFraction=movsum(double(sat),[W-1 0])./max(movsum(double(active),[W-1 0]),1);
variation=[0;abs(diff(trace.uL))+abs(diff(trace.uR))];variationRate=movsum(variation,[W-1 0])./max(duration,cfg.Ts);
correction=movmean(abs(trace.correction),[W-1 0]);
prms=sqrt(movmean(trace.P_term.^2,[W-1 0]));drms=sqrt(movmean(trace.D_term.^2,[W-1 0]));
residual=movmean(max(abs([trace.left_residual_mps trace.right_residual_mps]),[],2),[W-1 0]);
ready=t>=.6 & count>=.5*min((1:N).',W);
slow=ready & mae>.18 & correction<.12 & zcr<=1.5;
oscillation=ready & zcr>=3 & rmsE>.08;
saturation=ready & satFraction>.15;
integral=ready & abs(trace.I_term)>=.9*cfg.integral_limit;
chatter=ready & drms>1.5*max(prms,.005) & variationRate>3 & rmsE<.15;
mismatch=ready & residual>.005;
stable=ready & mae<=.18 & zcr<3 & satFraction<=.15 & ~mismatch & ~integral & ~chatter;
status=strings(N,1);message=status;
for k=1:N
    code=trace.stop_reason(k);
    if code==1,status(k)="Line-loss stop";message(k)=sprintf('No line detected for %.2f s; reset and check the settings.',cfg.loss_timeout_s);
    elseif code==2,status(k)="Out-of-bounds stop";message(k)="The body reference point is outside the map.";
    elseif code==3,status(k)="Numerical anomaly";message(k)="The pose contains a non-finite value; motor outputs are zero.";
    elseif code==4,status(k)="Time limit";message(k)="The configured simulation time limit was reached; motors stopped.";
    elseif mismatch(k),status(k)="Motor-model mismatch";message(k)=sprintf('Simulated-to-nominal speed residual: %.4f m/s. Check the motor parameters.',residual(k));
    elseif oscillation(k),status(k)="Significant oscillation";message(k)=sprintf('Error zero crossings %.1f/s, RMS %.3f; Kp may be high or Kd insufficient.',zcr(k),rmsE(k));
    elseif chatter(k),status(k)="Derivative chatter";message(k)=sprintf('D/P RMS ratio %.1f, command variation %.1f/s; try reducing Kd.',drms(k)/max(prms(k),.005),variationRate(k));
    elseif saturation(k),status(k)="Output saturation";message(k)=sprintf('Saturation in the last second: %.0f%%. Increasing gains may not help.',100*satFraction(k));
    elseif integral(k),status(k)="Integral near limit";message(k)="The integral term is near its configured limit; check for persistent steering bias.";
    elseif slow(k),status(k)="Slow response";message(k)=sprintf('Last-second MAE %.3f, correction %.3f; try increasing Kp.',mae(k),correction(k));
    elseif stable(k),status(k)="Tracking stable";message(k)=sprintf('Last-second MAE %.3f, zero crossings %.1f/s, saturation %.0f%%.',mae(k),zcr(k),100*satFraction(k));
    elseif ~valid(k),status(k)="Transient line loss";message(k)="Hold the previous error and freeze integration; persistent line loss triggers a stop.";
    else,status(k)="Observing";message(k)="Continue observing error, trajectory and output; no parameter diagnosis yet.";end
end
feedback=table(t,mae,rmsE,zcr,satFraction,variationRate,residual,slow,oscillation,saturation,integral,chatter,mismatch,stable,status,message, ...
 repmat(cfg.Kp,N,1),repmat(cfg.Ki,N,1),repmat(cfg.Kd,N,1), ...
 'VariableNames',{'time_s','window_mae','window_rms','zero_crossings_per_s','window_saturation_fraction','command_variation_per_s','window_speed_residual_mps', ...
 'slow_flag','oscillation_flag','saturation_flag','integral_limit_flag','derivative_chatter_flag','motor_mismatch_flag','stable_flag','status','message','Kp_tag','Ki_tag','Kd_tag'});
end
