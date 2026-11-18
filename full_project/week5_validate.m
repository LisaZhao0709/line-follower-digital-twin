function directory=week5_validate()
cfg=twin_config();addpath(fullfile(cfg.root,'kernels'));directory=fullfile(cfg.results_dir,['week5_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(directory);
diary(fullfile(directory,'matlab.log'));cleanup=onCleanup(@()diary('off'));build_twin(true);
names={'PID_default','PID_repeat','PD_no_I','PID_large_I','Sensor_dropout','No_line','Out_of_bounds','Timeout'};
cases={struct(),struct(),struct('Ki',0),struct('Ki',1),struct('dropout_start_s',1,'dropout_duration_s',.4,'stop_time',3), ...
 struct('x0',1,'y0',.8,'stop_time',1),struct('x0',-1,'stop_time',1),struct('stop_time',.1)};
records=cell(size(names));traces=cell(size(names));
for k=1:numel(names)
    [out,c]=twin_simulate(cases{k});[r,traces{k}]=twin_record(out,c,names{k},directory);records{k}=r;
end
records=[records{:}];
assert(records(1).completed_lap && records(3).completed_lap,'Default PID/PD must complete a lap.');
assert(isequaln(traces{1},traces{2}),'Reset/repeat mismatch.');
assert(records(5).stop_reason==1 && abs(records(5).stop_time_s-1.2)<1e-10);
assert(records(6).stop_reason==1 && abs(records(6).stop_time_s-.2)<1e-10);
assert(records(7).stop_reason==2 && records(7).stop_time_s==0);
assert(records(8).stop_reason==4 && abs(records(8).stop_time_s-.1)<1e-10);
assert(all(traces{3}.I_term==0));assert(max(abs(traces{4}.I_term))<=cfg.integral_limit+1e-12);
assert(all(traces{5}.uL(traces{5}.time_s>=1.2)==0) && all(traces{5}.uR(traces{5}.time_s>=1.2)==0));
% Formula-focused tests cover numeric faults, timer recovery, clamping and unwind.
clear integral_aw;for k=1:100,[I,b]=integral_aw(1,1,0,1,2,.02,.2,.35,1);assert(I==0 && b==1);end
clear integral_aw;for k=1:100,[I,~]=integral_aw(1,0,0,1,2,.02,.2,.35,0);end;assert(abs(I-.2)<1e-12);
[frozen,~]=integral_aw(-1,0,0,0,2,.02,.2,.35,1);assert(frozen==I);
[unwound,~]=integral_aw(-1,1,0,1,2,.02,.2,.35,1);assert(unwound<I);
[zero,~]=integral_aw(1,0,0,1,0,.02,.2,.35,1);assert(zero==0);
clear full_guard;[en,~,~,reason]=full_guard(1,.02,.2,NaN,0,0,2,2,0,100);assert(en==0 && reason==3);
clear full_guard;for k=0:9,[en,~,~,~]=full_guard(0,.02,.2,1,1,0,2,2,k*.02,100);assert(en==1);end
[en,~,~,reason]=full_guard(1,.02,.2,1,1,0,2,2,.2,100);assert(en==1 && reason==0);
invalid={struct('Kp',NaN),struct('Ki',-1),struct('Kd',Inf),struct('Ts',0),struct('Kp',21)};
for k=1:numel(invalid),rejected=false;try,twin_config(invalid{k});catch,rejected=true;end;assert(rejected);end
writetable(struct2table(records),fullfile(directory,'summary.csv'));
status=struct('week',5,'passed',true,'actual_simulink_cases',numel(names),'equation_checks',25*numel(names),'repeat_exact',true,'unit_and_invalid_input_checks',true);
twin_write_json(fullfile(directory,'status.json'),status);
fid=fopen(fullfile(cfg.results_dir,'week5_latest.txt'),'w');fprintf(fid,'%s',directory);fclose(fid);
fprintf('WEEK5_PASSED %s\n',directory);
end
