function directory=week8_validate(directory)
cfg=twin_config();
for week=5:7,s=jsondecode(fileread(fullfile(twin_latest(week),'status.json')));assert(s.passed);end
reuse=nargin>0;
if ~reuse,directory=fullfile(cfg.results_dir,['week8_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(directory);end
diary(fullfile(directory,'matlab.log'));cleaner=onCleanup(@()diary('off'));
names={'PID_final_repeat','PID_10ms','PID_5ms','PID_initial_offset'};
cases={struct(),struct('Ts',.01),struct('Ts',.005),struct('y0',cfg.y0+.008)};
records=cell(size(names));performance=cell(size(names));
for k=1:numel(names)
    if reuse,S=load(fullfile(directory,[names{k} '_run.mat']),'out','cfg');out=S.out;c=S.cfg;else,[out,c]=twin_simulate(cases{k});end
    [r,tr]=twin_record(out,c,names{k},directory);assert(r.completed_lap);records{k}=r;
    fb=twin_feedback(tr,c);writetable(fb,fullfile(directory,[names{k} '_feedback.csv']));
    info=out.SimulationMetadata.TimingInfo;
    performance{k}=struct('case_name',names{k},'simulated_time_s',c.stop_time,'samples',height(tr), ...
        'initialization_wall_s',info.InitializationElapsedWallTime,'execution_wall_s',info.ExecutionElapsedWallTime, ...
        'termination_wall_s',info.TerminationElapsedWallTime,'total_wall_s',info.TotalElapsedWallTime);
    assert(info.ExecutionElapsedWallTime<c.stop_time,'Simulation execution is slower than simulated time.');
end
records=[records{:}];writetable(struct2table(records),fullfile(directory,'summary.csv'));
writetable(struct2table([performance{:}]),fullfile(directory,'performance.csv'));
old=load(fullfile(twin_latest(5),'PID_default_run.mat'),'out');new=load(fullfile(directory,'PID_final_repeat_run.mat'),'out');
for n={'x','y','theta','error','P_term','I_term','D_term','uL_log','uR_log','sensors','stop_reason'}
    [~,a]=series_data(old.out,n{1});[~,b]=series_data(new.out,n{1});assert(isequal(a,b),'Final repeat mismatch: %s',n{1});
end
addpath(fullfile(cfg.root,'kernels'));clear full_guard;
for k=0:11,[en,~,~,reason]=full_guard(0,.02,.21,1,1,0,2,2,k*.02,100);if k<11,assert(en==1);else,assert(en==0 && reason==1);end,end
load_system(fullfile(cfg.models_dir,'LineFollowerTwin.slx'));
assert(strcmp(get_param('LineFollowerTwin/MotorCommands/LeftEnable','BlockType'),'Switch'));
assert(strcmp(get_param('LineFollowerTwin/MotorCommands/SafeZero','Value'),'0'));
assert(strcmp(get_param('LineFollowerTwin','Solver'),'FixedStepDiscrete'));
% Regression includes final teaching rules in the actual MATLAB UI.
app=twin_app('off');cleanupUI=onCleanup(@()app.actions.close());
q=guidata(app.figure);q.index=2000;guidata(app.figure,q);app.actions.step();q=guidata(app.figure);
assert(isfield(q,'feedback') && any(contains(string(app.status.String),q.feedback.status(q.index))));
set(app.figure,'Visible','on');drawnow;frame=getframe(app.figure);imwrite(frame.cdata,fullfile(directory,'interface_PID.png'));
for entry={'P_weak','P_extreme'}
    n=entry{1};S=load(fullfile(twin_latest(7),[n '_run.mat']),'cfg','record');q=guidata(app.figure);
    q.cfg=S.cfg;q.record=S.record;q.trace=readtable(fullfile(twin_latest(7),[n '_trace.csv']));q=rmfield(q,'feedback');
    if strcmp(n,'P_weak'),q.index=q.record.analysis_end_index-1;else,q.index=1000;end
    guidata(app.figure,q);set(app.fields(1),'String',num2str(q.cfg.Kp));set(app.fields(2),'String',num2str(q.cfg.Ki));set(app.fields(3),'String',num2str(q.cfg.Kd));
    app.actions.step();drawnow;frame=getframe(app.figure);imwrite(frame.cdata,fullfile(directory,['interface_' n '.png']));
end
app.actions.reset();q=guidata(app.figure);assert(q.index==1 && ~q.playing);app.actions.close();
environment=struct('matlab_version',version,'release',version('-release'),'computer',computer,'simulink_license',license('test','Simulink'), ...
 'products',{ver},'client_timezone','Asia/Shanghai','checked_at',char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyy-MM-dd HH:mm:ss Z')));
twin_write_json(fullfile(directory,'environment.json'),environment);
twin_write_json(fullfile(directory,'status.json'),struct('week',8,'matlab_passed',true,'passed',false,'independent_review_pending',true,'actual_simulink_cases',4,'equation_checks',100,'repeat_exact',true,'final_UI_regression',true));
fid=fopen(fullfile(cfg.results_dir,'week8_latest.txt'),'w');fprintf(fid,'%s',directory);fclose(fid);
fprintf('WEEK8_MATLAB_PASSED independent review pending: %s\n',directory);
end
