function [I,blocked]=integral_aw(e,P,D,detected,Ki,Ts,limit,base,useAW)
%#codegen
% Bounded integral OUTPUT. Conditional integration uses downstream motor limits.
persistent state
if isempty(state),state=0;end
blocked=0;
if Ki==0,state=0;elseif detected
    delta=Ki*e*Ts;
    candidate=min(max(state+delta,-limit),limit);
    total=P+D+candidate;
    authority=min(base,1-base); % either wheel saturates beyond this correction
    if useAW && abs(total)>authority && total*delta>0
        blocked=1;
    else
        state=candidate;
    end
end
I=state;
end
