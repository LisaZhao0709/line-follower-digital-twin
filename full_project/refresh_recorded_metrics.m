function refresh_recorded_metrics()
% Re-evaluate ACTUAL saved runs after metric corrections; never invent new traces.
for week=[5 7]
    directory=twin_latest(week);summary=readtable(fullfile(directory,'summary.csv'),'TextType','string');rows=cell(height(summary),1);
    for k=1:height(summary)
        name=char(summary.case_name(k));S=load(fullfile(directory,[name '_run.mat']),'out','cfg');
        [r,tr]=twin_record(S.out,S.cfg,name,directory);
        if week==7
            fb=twin_feedback(tr,S.cfg);writetable(fb,fullfile(directory,[name '_feedback.csv']));
            for flag={'slow','oscillation','saturation','integral_limit','derivative_chatter','motor_mismatch','stable'}
                f=flag{1};r.([f '_samples'])=nnz(fb.([f '_flag'])(1:r.analysis_end_index));
            end
        end
        rows{k}=r;
    end
    writetable(struct2table([rows{:}]),fullfile(directory,'summary.csv'));
end
fprintf('RECORDED_METRICS_RECHECKED: safety-disabled zero outputs excluded from saturation.\n');
end
