function [t,data] = series_data(out,name)
% Normalize scalar and 1x8 Timeseries arrays to sample-by-channel matrices.
ts=out.get(name);
t=double(ts.Time(:));
if ts.IsTimeFirst
    data=reshape(double(ts.Data),numel(t),[]);
else
    data=reshape(double(ts.Data),[],numel(t)).';
end
end
