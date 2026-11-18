function [strength,binary]=sensor_fault(clean,t,start,duration,noise,threshold,environment)
%#codegen
% Optical errors affect the observed strengths before thresholding and control.
strength=zeros(1,8);binary=zeros(1,8);
for k=1:8
    value=environment(1)*clean(k)+environment(2)+environment(k+4) ...
        +noise*sin(2*pi*(7+k)*t+.37*k);
    strength(k)=min(max(value,0),1);
    if t>=start-1e-12 && t<start+duration-1e-12,strength(k)=0;end
    binary(k)=double(strength(k)>=threshold);
end
end
