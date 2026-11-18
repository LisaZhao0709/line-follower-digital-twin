function build_exact_models(force)
% Add exact zero-order-held kinematics; preserve the original teaching models.
if nargin<1,force=false;end
build_models();cfg=project_config();load_system('simulink');
for base={'LF_Week2_OpenLoop','LF_Week4_PD'}
    original=base{1};model=[original '_Exact'];
    target=fullfile(cfg.models_dir,[model '.slx']);
    if isfile(target) && ~force,continue;end
    if bdIsLoaded(model)
        assert(strcmp(get_param(model,'Dirty'),'off'),'Save edits before rebuilding %s.',model);
        close_system(model,0);
    end
    if isfile(target)
        backup=fullfile(cfg.models_dir,'backups');if ~isfolder(backup),mkdir(backup);end
        copyfile(target,fullfile(backup,[model '_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.slx']));
    end
    load_system(fullfile(cfg.models_dir,[original '.slx']));
    assert(strcmp(get_param(original,'Dirty'),'off'),'Save edits to %s before cloning.',original);
    save_system(original,target);
    if bdIsLoaded(original),close_system(original,0);end
    load_system(target);s=[model '/DifferentialDrive'];
    mw=get_param(model,'ModelWorkspace');local=getVariable(mw,'cfg');
    local.integration_method='exact_zoh';assignin(mw,'cfg',local);
    if contains(original,'Week4')
        guard=get_param([model '/MotorCommands/LossGuard'],'MATLABFunctionConfiguration');
        guard.FunctionScript=fileread(fullfile(cfg.root,'kernels','loss_guard.m'));
    end
    delete_line(s,'Theta/1','CosTheta/1');delete_line(s,'Theta/1','SinTheta/1');
    delete_line(s,'AverageSpeed/1','Xdot/1');delete_line(s,'AverageSpeed/1','Ydot/1');
    set_param([s '/CosTheta'],'Position',[610 30 665 65]);
    set_param([s '/SinTheta'],'Position',[610 95 665 130]);
    set_param([s '/Xdot'],'Position',[785 25 825 65]);
    set_param([s '/Ydot'],'Position',[785 95 825 135]);
    set_param([s '/X'],'Position',[875 25 940 65]);
    set_param([s '/Y'],'Position',[875 95 940 135]);
    set_param([s '/x'],'Position',[995 35 1025 55]);
    set_param([s '/y'],'Position',[995 105 1025 125]);
    set_param([s '/theta'],'Position',[995 165 1025 185]);
    add_block('simulink/Math Operations/Gain',[s '/HalfTurn'],'Position',[370 240 440 275],'Gain','cfg.Ts/2');
    add_block('simulink/Math Operations/Sum',[s '/MidpointHeading'],'Position',[530 40 565 85],'Inputs','++');
    add_block('simulink/User-Defined Functions/MATLAB Function',[s '/ArcFactor'],'Position',[515 230 645 285]);
    conf=get_param([s '/ArcFactor'],'MATLABFunctionConfiguration');
    conf.FunctionScript=fileread(fullfile(cfg.root,'kernels','arc_factor.m'));
    add_block('simulink/Math Operations/Product',[s '/EffectiveSpeed'],'Position',[710 240 755 285],'Inputs','2');
    add_line(s,'InverseWheelbase/1','HalfTurn/1','autorouting','on');
    add_line(s,'Theta/1','MidpointHeading/1','autorouting','on');
    add_line(s,'HalfTurn/1','MidpointHeading/2','autorouting','on');
    add_line(s,'MidpointHeading/1','CosTheta/1','autorouting','on');
    add_line(s,'MidpointHeading/1','SinTheta/1','autorouting','on');
    add_line(s,'HalfTurn/1','ArcFactor/1','autorouting','on');
    add_line(s,'AverageSpeed/1','EffectiveSpeed/1','autorouting','on');
    add_line(s,'ArcFactor/1','EffectiveSpeed/2','autorouting','on');
    add_line(s,'EffectiveSpeed/1','Xdot/1','autorouting','on');
    add_line(s,'EffectiveSpeed/1','Ydot/1','autorouting','on');
    notes=find_system(s,'FindAll','on','Type','annotation');
    for k=1:numel(notes)
        a=get_param(notes(k),'Object');a.Text=sprintf(['EXACT ZOH KINEMATICS: commands held for Ts. h=omega*Ts/2.\n' ...
            'dx_avg=v*sinc(h)*cos(theta+h), dy_avg=v*sinc(h)*sin(theta+h).\n' ...
            'Native state integrators accumulate these exact interval increments.\n' ...
            'Exact for the assumed ideal kinematic model; hardware accuracy still needs measurements.']);
        a.Position=[120 340];
    end
    save_system(model,target);fprintf('Generated accurate kinematics: %s\n',target);
end
end
