function probe_teaching_gains()
cfg=twin_config();directory=fullfile(cfg.results_dir,'gain_probe');if ~isfolder(directory),mkdir(directory);end
for gain=[10 15 20]
    name=sprintf('P_%g',gain);[out,c]=twin_simulate(struct('Kp',gain,'Ki',0,'Kd',0));
    [r,tr]=twin_record(out,c,name,directory);fb=twin_feedback(tr,c);writetable(fb,fullfile(directory,[name '_feedback.csv']));
    fprintf('PROBE gain=%g zcrmax=%.1f RMSmax=%.3f oscillation=%d\n',gain,max(fb.zero_crossings_per_s),max(fb.window_rms),nnz(fb.oscillation_flag(1:r.analysis_end_index)));
end
end
