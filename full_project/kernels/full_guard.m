function [enabled,offTrack,missingSeconds,reason]=full_guard(detected,Ts,timeout,x,y,theta,width,height,t,horizon)
%#codegen
% Latched stop reason: 0 run, 1 lost line, 2 out of bounds, 3 numeric, 4 timeout.
persistent elapsed active stopped code
if isempty(elapsed),elapsed=0;active=false;stopped=false;code=0;end
if detected,elapsed=0;active=false;elseif active,elapsed=elapsed+Ts;else,elapsed=0;active=true;end
if ~stopped
    if ~isfinite(x) || ~isfinite(y) || ~isfinite(theta),code=3;
    elseif x<0 || y<0 || x>width || y>height,code=2;
    elseif elapsed>=timeout-1e-12,code=1;
    elseif t>=horizon-1e-12,code=4;
    end
    stopped=code~=0;
end
enabled=double(~stopped);offTrack=double(code==1);missingSeconds=elapsed;reason=code;
end
