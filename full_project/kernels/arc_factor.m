function factor = arc_factor(halfTurn)
%#codegen
% sin(h)/h; exact displacement factor for constant twist over one sample.
if abs(halfTurn)<1e-4
    h2=halfTurn*halfTurn;
    factor=1-h2/6+h2*h2/120;
else
    factor=sin(halfTurn)/halfTurn;
end
end
