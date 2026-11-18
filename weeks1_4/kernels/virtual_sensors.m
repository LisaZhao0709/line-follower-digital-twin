function [strength,binary,sensorX,sensorY] = virtual_sensors(x,y,theta,map,scale,front,spacing,threshold)
%#codegen
% S1..S8 run LEFT to RIGHT as seen looking forward. Outside-map values are zero.
strength=zeros(1,8); binary=zeros(1,8);
sensorX=zeros(1,8); sensorY=zeros(1,8);
[H,W]=size(map);
ct=cos(theta); st=sin(theta);
for i=1:8
    localY=(4.5-i)*spacing;
    X=x+ct*front-st*localY;
    Y=y+st*front+ct*localY;
    sensorX(i)=X; sensorY(i)=Y;
    col=1+X/scale; row=H-Y/scale;
    if col>=1 && col<=W && row>=1 && row<=H
        c0=floor(col); r0=floor(row);
        c1=min(c0+1,W); r1=min(r0+1,H);
        dc=col-c0; dr=row-r0;
        strength(i)=(1-dr)*((1-dc)*map(r0,c0)+dc*map(r0,c1)) ...
                   +dr*((1-dc)*map(r1,c0)+dc*map(r1,c1));
    end
    binary(i)=double(strength(i)>=threshold);
end
end
