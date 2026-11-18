function input=twin_environment(cfg)
% Recorded exogenous disturbances use a private stream, independent of PID/RNG.
% Columns: time, light gain, shadow bias, forward/lateral jitter, eight read errors.
t=(0:round(cfg.stop_time/cfg.Ts)).'*cfg.Ts;
N=numel(t);input=[t ones(N,1) zeros(N,11)];
if ~isfield(cfg,'environment_level') || cfg.environment_level==0,return;end
stream=RandStream('mt19937ar','Seed',cfg.environment_seed);
% Teaching scenarios. Magnitudes require calibration against physical sensors.
if cfg.environment_level==1
    light=.04;shadow=.08;jitter=.0006;readNoise=.015;channelBias=.005;
else
    light=.12;shadow=.25;jitter=.002;readNoise=.06;channelBias=.015;
end
taus=[2 .8 .08 .08];colored=zeros(N,4);
colored(1,:)=randn(stream,1,4);
alpha=exp(-cfg.Ts./taus);
innovations=randn(stream,N-1,4);
for k=2:N
    colored(k,:)=alpha.*colored(k-1,:)+sqrt(1-alpha.^2).*innovations(k-1,:);
end
input(:,2)=min(max(1+light*colored(:,1),.5),1.5);
input(:,3)=min(shadow*max(colored(:,2),0),.6);
input(:,4:5)=jitter*colored(:,3:4);
bias=channelBias*randn(stream,1,8);
input(:,6:13)=readNoise*randn(stream,N,8)+bias;
end
