function directory=run_detailed_review()
% Complete traceable review. Every invocation gets a separate immutable result folder.
cfg=project_config();stamp=char(datetime('now','TimeZone','Asia/Shanghai','Format','yyyyMMdd_HHmmss'));
directory=fullfile(cfg.results_dir,['review_' stamp]);
assert(~isfolder(directory),'Review directory already exists; start another run.');mkdir(directory);
fid=fopen(fullfile(cfg.results_dir,'review_latest.txt'),'w','n','UTF-8');fprintf(fid,'%s',directory);fclose(fid);
diary(fullfile(directory,'matlab_run.log'));finish=onCleanup(@()diary('off'));
fprintf('Review started %s (Asia/Shanghai)\n',stamp);
fprintf('MATLAB %s, Simulink license %d\n',version,license('test','Simulink'));
addpath(cfg.root,fullfile(cfg.root,'kernels'));
environment.version=version;environment.release=version('-release');environment.computer=computer;
environment.products=ver;environment.source='actual local MATLAB/Simulink normal-mode execution';
write_json(fullfile(directory,'environment.json'),environment);
sync_loss_guard();build_exact_models(true);
snapshot=fullfile(directory,'source_snapshot');mkdir(snapshot);mkdir(fullfile(snapshot,'kernels'));mkdir(fullfile(snapshot,'models'));mkdir(fullfile(snapshot,'data'));
sourceFiles=dir(fullfile(cfg.root,'*.m'));
for k=1:numel(sourceFiles),copyfile(fullfile(sourceFiles(k).folder,sourceFiles(k).name),snapshot);end
copyfile(fullfile(cfg.root,'kernels','*.m'),fullfile(snapshot,'kernels'));
for m={'LF_Week2_OpenLoop','LF_Week4_PD','LF_Week2_OpenLoop_Exact','LF_Week4_PD_Exact'}
    copyfile(fullfile(cfg.models_dir,[m{1} '.slx']),fullfile(snapshot,'models'));
end
for f={'track_data.mat','track_source.png','track_mask.png','map_metadata.json'}
    copyfile(fullfile(cfg.root,'data',f{1}),fullfile(snapshot,'data'));
end
review_open_loop(directory);review_safety_and_lap_tests(directory);
cases={ ...
    'Euler_PD_20ms','LF_Week4_PD',struct('integration_method','euler'); ...
    'Exact_P_weak','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','Kp',.05,'Kd',0); ...
    'Exact_P_20ms','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','Kd',0); ...
    'Exact_PD_20ms','LF_Week4_PD_Exact',struct('integration_method','exact_zoh'); ...
    'Exact_PD_repeat','LF_Week4_PD_Exact',struct('integration_method','exact_zoh'); ...
    'Exact_PD_10ms','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','Ts',.01); ...
    'Exact_PD_5ms','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','Ts',.005); ...
    'Exact_PD_front_minus10pct','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','sensor_front_m',.045); ...
    'Exact_PD_front_plus10pct','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','sensor_front_m',.055); ...
    'Exact_PD_motor_minus10pct','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','km',.315); ...
    'Exact_PD_motor_plus10pct','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','km',.385); ...
    'Exact_PD_initial_no_line','LF_Week4_PD_Exact',struct('integration_method','exact_zoh','x0',-1,'y0',-1,'stop_time',.5)};
for k=1:size(cases,1)
    name=cases{k,1};model=cases{k,2};
    fprintf('SIMULATION %d/%d %s\n',k,size(cases,1),name);
    [out,c]=simulate_case(model,cases{k,3});
    r=audit_run(out,c,name,model,directory);
    if k==1,records=r;else,records(k)=r;end
    if k==4,baseline=out;end
    if k==5
        signals={'x','y','theta','error','P_term','D_term','uL_log','uR_log','sensors','off_track'};
        repeatRows={};
        for j=1:numel(signals)
            [~,a]=series_data(baseline,signals{j});[~,b]=series_data(out,signals{j});
            delta=max(abs(a-b),[],'all');assert(delta<1e-12);
            repeatRows(end+1,:)={signals{j},delta,true};
        end
        writetable(cell2table(repeatRows,'VariableNames',{'signal','max_absolute_difference','passed'}), ...
            fullfile(directory,'repeatability.csv'));
    end
    if strcmp(name,'Exact_PD_initial_no_line')
        assert(abs(r.stop_time_s-c.loss_timeout_s)<1e-12,'Loss duration is not exactly 0.2 s from first missing sample.');
        assert(isnan(r.mae_sensor_error),'No detected samples must yield undefined MAE, not zero.');
    end
    summary=struct2table(records);writetable(summary,fullfile(directory,'simulation_summary.csv'));
end
assert(records(3).completed_lap && records(4).completed_lap && ~records(4).stopped_off_track);
assert(records(2).stopped_off_track && ~records(2).completed_lap);
assert(records(6).completed_lap && records(7).completed_lap,'Sampling sensitivity produced loss; investigate before claiming convergence.');
write_json(fullfile(directory,'matlab_status.json'),struct('all_mandatory_checks_passed',true, ...
    'actual_simulation_cases',size(cases,1),'analytical_cases',12,'equation_checks_per_run',14));
fprintf('DETAILED_MATLAB_REVIEW_PASSED\nResults: %s\n',directory);
end

function write_json(file,value)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));
end
