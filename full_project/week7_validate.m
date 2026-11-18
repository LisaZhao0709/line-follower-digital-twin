function directory=week7_validate(directory)
assert(isfile(fullfile(twin_latest(6),'status.json')));cfg=twin_config();
reuse=nargin>0;
if ~reuse,directory=fullfile(cfg.results_dir,['week7_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(directory);end
diary(fullfile(directory,'matlab.log'));cleaner=onCleanup(@()diary('off'));
names={'P_weak','P_nominal','P_high','P_extreme','PD_high','PID_default','PID_integral','PID_no_AW','PID_extreme_I','PD_noise','PD_large_D','Motor_mismatch','Dropout'};
cases={struct('Kp',.05,'Ki',0,'Kd',0),struct('Ki',0,'Kd',0),struct('Kp',3,'Ki',0,'Kd',0), ...
 struct('Kp',15,'Ki',0,'Kd',0),struct('Kp',3,'Ki',0,'Kd',.08),struct(),struct('Ki',1),struct('Ki',1,'anti_windup',false), ...
 struct('Ki',2),struct('Ki',0,'sensor_noise',.08),struct('Ki',0,'Kd',.5), ...
 struct('motor_left_factor',.8),struct('dropout_start_s',1,'dropout_duration_s',.4,'stop_time',3)};
records=cell(size(names));feedbacks=cell(size(names));
for k=1:numel(names)
    if reuse
        S=load(fullfile(directory,[names{k} '_run.mat']),'cfg','record');c=S.cfg;r=S.record;
        tr=readtable(fullfile(directory,[names{k} '_trace.csv']));
    else
        [out,c]=twin_simulate(cases{k});[r,tr]=twin_record(out,c,names{k},directory);
    end
    fb=twin_feedback(tr,c);feedbacks{k}=fb;
    writetable(fb,fullfile(directory,[names{k} '_feedback.csv']));
    keep=1:r.analysis_end_index;flags={'slow','oscillation','saturation','integral_limit','derivative_chatter','motor_mismatch','stable'};
    for j=1:numel(flags),r.([flags{j} '_samples'])=nnz(fb.([flags{j} '_flag'])(keep));end
    records{k}=r;
    fprintf('FEEDBACK %s slow=%d oscillation=%d stable=%d\n',names{k},r.slow_samples,r.oscillation_samples,r.stable_samples);
end
records=[records{:}];writetable(struct2table(records),fullfile(directory,'summary.csv'));
assert(records(6).completed_lap && records(6).stable_samples>0);
assert(records(1).slow_samples>0 && records(1).stop_reason==1,'Weak P must exhibit slow correction before lost line.');
assert(records(3).oscillation_samples>0 || records(4).oscillation_samples>0,'Strong P must demonstrate measured oscillation.');
assert(records(12).motor_mismatch_samples>0 && records(12).max_speed_residual>.005);
assert(records(13).stop_reason==1 && abs(records(13).stop_time_s-1.2)<1e-10);
old=load(fullfile(twin_latest(5),'PID_default_run.mat'),'record');assert(abs(records(6).lap_time_s-old.record.lap_time_s)<1e-12);
% No-data windows are undefined; error sign chatter inside deadband is not oscillation.
noLine=readtable(fullfile(twin_latest(5),'No_line_trace.csv'));none=twin_feedback(noLine,cfg);
assert(all(isnan(none.window_mae)) && all(isnan(none.window_rms)));
assert(all(feedbacks{13}.status(feedbacks{13}.time_s>=1.2)=="Line-loss stop"),'Stop must remain latched after telemetry recovers.');
tr=readtable(fullfile(directory,'PID_default_trace.csv'));tr.sensor_error(:)=.02*sin(2*pi*10*tr.time_s);
fb=twin_feedback(tr,cfg);assert(all(fb.zero_crossings_per_s==0));
twin_write_json(fullfile(directory,'status.json'),struct('week',7,'passed',true,'actual_simulink_cases',numel(names),'equation_checks',25*numel(names),'behavior_rules_verified',true,'deadband_and_no_data_tests',true));
fid=fopen(fullfile(cfg.results_dir,'week7_latest.txt'),'w');fprintf(fid,'%s',directory);fclose(fid);
fprintf('WEEK7_PASSED %s\n',directory);
end
