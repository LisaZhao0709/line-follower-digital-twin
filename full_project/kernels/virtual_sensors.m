function [strength,binary,sensorX,sensorY,ideal] = virtual_sensors(x,y,theta,map,scale,front,spacing,threshold,environment)
%#codegen
% S1..S8 run LEFT to RIGHT as seen looking forward. Outside-map values are zero.
strength=zeros(1,8); binary=zeros(1,8);ideal=zeros(1,8);
sensorX=zeros(1,8); sensorY=zeros(1,8);
ct=cos(theta); st=sin(theta);
for i=1:8
    localY=(4.5-i)*spacing;
    nominalX=x+ct*front-st*localY;
    nominalY=y+st*front+ct*localY;
    ideal(i)=sample_map(map,scale,nominalX,nominalY);
    X=nominalX+ct*environment(3)-st*environment(4);
    Y=nominalY+st*environment(3)+ct*environment(4);
    sensorX(i)=X; sensorY(i)=Y;
    strength(i)=sample_map(map,scale,X,Y);
    binary(i)=double(strength(i)>=threshold);
end
end
function value=sample_map(map,scale,X,Y)
[H,W]=size(map);col=1+X/scale;row=H-Y/scale;value=0;
if col>=1 && col<=W && row>=1 && row<=H
    c0=floor(col);r0=floor(row);c1=min(c0+1,W);r1=min(r0+1,H);
    dc=col-c0;dr=row-r0;
    value=(1-dr)*((1-dc)*map(r0,c0)+dc*map(r0,c1)) ...
        +dr*((1-dc)*map(r1,c0)+dc*map(r1,c1));
end
end
