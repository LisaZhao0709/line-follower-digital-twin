function [enabled,offTrack,missingSeconds] = loss_guard(detected,Ts,timeout)
%#codegen
% Minimal protection: after continuous loss, latch STOP until a fresh run/reset.
persistent elapsed active stopped
if isempty(elapsed),elapsed=0;active=false;stopped=false;end
if detected
    elapsed=0;active=false;
elseif active
    elapsed=elapsed+Ts;
else
    elapsed=0;active=true; % the first missing sample marks the start of loss
end
if elapsed>=timeout-1e-12,stopped=true;end
enabled=double(~stopped);
offTrack=double(stopped);
missingSeconds=elapsed;
end
