function [error,detected] = line_error(strength,binary)
%#codegen
% Positive error: black line is on the LEFT, so increase right-side speed.
detected=double(any(binary>0.5));
error=0;
if detected
    total=0; weighted=0;
    for i=1:8
        total=total+strength(i);
        weighted=weighted+strength(i)*(4.5-i);
    end
    error=weighted/(3.5*max(total,1e-12));
end
end
