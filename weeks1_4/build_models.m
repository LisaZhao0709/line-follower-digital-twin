function build_models(force)
% Generate editable native Simulink diagrams; user does not need to drag blocks.
if nargin<1, force=false; end
cfg=project_config();
addpath(cfg.root,fullfile(cfg.root,'kernels'));
load_system('simulink');
for entry = {'LF_Week2_OpenLoop','LF_Week4_PD'}
    model=entry{1}; target=fullfile(cfg.models_dir,[model '.slx']);
    if isfile(target) && ~force, continue; end
    if bdIsLoaded(model)
        assert(strcmp(get_param(model,'Dirty'),'off'), ...
            'Save your edits before rebuilding %s.',model);
        close_system(model,0);
    end
    if isfile(target)
        backup=fullfile(cfg.models_dir,'backups');
        if ~isfolder(backup),mkdir(backup);end
        copyfile(target,fullfile(backup,[model '_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.slx']));
    end
    new_system(model);
    set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
        'FixedStep','cfg.Ts','StopTime','cfg.stop_time', ...
        'ReturnWorkspaceOutputs','on','SaveTime','on','SaveOutput','off', ...
        'SignalLogging','off','SaveFormat','Dataset');
    mw=get_param(model,'ModelWorkspace'); assignin(mw,'cfg',cfg);
    assignin(mw,'Kp',cfg.Kp); assignin(mw,'Kd',cfg.Kd);
    assignin(mw,'uL',0.5); assignin(mw,'uR',0.5);
    make_plant(model,cfg);
    if strcmp(model,'LF_Week2_OpenLoop')
        make_open_loop(model);
    else
        make_closed_loop(model,cfg);
    end
    save_system(model,target);
    fprintf('Generated %s\n',target);
end
end

function block(sys,lib,name,pos,varargin)
add_block(['simulink/' lib],[sys '/' name],'Position',pos,varargin{:});
end
function wire(sys,src,dst,name)
h=add_line(sys,src,dst,'autorouting','on');
if nargin==4,set_param(h,'Name',name);end
end
function empty_subsystem(sys,name,pos)
block(sys,'Ports & Subsystems/Subsystem',name,pos);
Simulink.SubSystem.deleteContents([sys '/' name]);
end
function note(sys,text,pos)
a=Simulink.Annotation(sys,strrep(text,'\n',newline)); a.Position=pos;
end
function logger(sys,src,name,pos)
block(sys,'Sinks/To Workspace',['Log_' name],pos, ...
    'VariableName',name,'SaveFormat','Timeseries','MaxDataPoints','inf','SampleTime','-1');
wire(sys,src,['Log_' name '/1']);
end
function matlab_block(sys,name,pos,file)
block(sys,'User-Defined Functions/MATLAB Function',name,pos);
conf=get_param([sys '/' name],'MATLABFunctionConfiguration');
conf.FunctionScript=fileread(file);
end

function make_plant(model,cfg)
empty_subsystem(model,'DifferentialDrive',[1020 110 1230 265]);
s=[model '/DifferentialDrive'];
block(s,'Ports & Subsystems/In1','LeftCommand',[25 35 55 55],'Port','1');
block(s,'Ports & Subsystems/In1','RightCommand',[25 105 55 125],'Port','2');
block(s,'Math Operations/Gain','LeftMotor',[95 30 150 65],'Gain','cfg.km');
block(s,'Math Operations/Gain','RightMotor',[95 100 150 135],'Gain','cfg.km');
block(s,'Math Operations/Sum','SpeedSum',[210 35 240 85],'Inputs','++');
block(s,'Math Operations/Gain','AverageSpeed',[275 45 330 75],'Gain','0.5');
block(s,'Math Operations/Sum','RightMinusLeft',[210 130 240 180],'Inputs','+-');
block(s,'Math Operations/Gain','InverseWheelbase',[275 140 330 170],'Gain','1/cfg.wheel_base_m');
block(s,'Discrete/Discrete-Time Integrator','Theta',[380 140 445 175], ...
    'gainval','1','SampleTime','cfg.Ts','InitialCondition','cfg.theta0','IntegratorMethod','Integration: Forward Euler');
block(s,'Math Operations/Trigonometric Function','CosTheta',[490 30 545 65],'Operator','cos');
block(s,'Math Operations/Trigonometric Function','SinTheta',[490 95 545 130],'Operator','sin');
block(s,'Math Operations/Product','Xdot',[590 25 625 65],'Inputs','2');
block(s,'Math Operations/Product','Ydot',[590 95 625 135],'Inputs','2');
block(s,'Discrete/Discrete-Time Integrator','X',[675 25 735 65], ...
    'gainval','1','SampleTime','cfg.Ts','InitialCondition','cfg.x0','IntegratorMethod','Integration: Forward Euler');
block(s,'Discrete/Discrete-Time Integrator','Y',[675 95 735 135], ...
    'gainval','1','SampleTime','cfg.Ts','InitialCondition','cfg.y0','IntegratorMethod','Integration: Forward Euler');
block(s,'Ports & Subsystems/Out1','x',[790 35 820 55],'Port','1');
block(s,'Ports & Subsystems/Out1','y',[790 105 820 125],'Port','2');
block(s,'Ports & Subsystems/Out1','theta',[790 165 820 185],'Port','3');
wire(s,'LeftCommand/1','LeftMotor/1');wire(s,'RightCommand/1','RightMotor/1');
wire(s,'LeftMotor/1','SpeedSum/1');wire(s,'RightMotor/1','SpeedSum/2');
wire(s,'SpeedSum/1','AverageSpeed/1');
wire(s,'RightMotor/1','RightMinusLeft/1');wire(s,'LeftMotor/1','RightMinusLeft/2');
wire(s,'RightMinusLeft/1','InverseWheelbase/1');wire(s,'InverseWheelbase/1','Theta/1');
wire(s,'Theta/1','CosTheta/1');wire(s,'Theta/1','SinTheta/1');
wire(s,'AverageSpeed/1','Xdot/1');wire(s,'CosTheta/1','Xdot/2');
wire(s,'AverageSpeed/1','Ydot/1');wire(s,'SinTheta/1','Ydot/2');
wire(s,'Xdot/1','X/1');wire(s,'Ydot/1','Y/1');
wire(s,'X/1','x/1');wire(s,'Y/1','y/1');wire(s,'Theta/1','theta/1');
note(s,'WEEK 2: x,y in m; theta in rad. Right faster => LEFT turn.\nNative blocks, forward Euler, Ts=0.02 s. Motor gains are assumptions.',[100 225]);
logger(model,'DifferentialDrive/1','x',[1340 95 1440 125]);
logger(model,'DifferentialDrive/2','y',[1340 145 1440 175]);
logger(model,'DifferentialDrive/3','theta',[1340 195 1440 225]);
block(model,'Signal Routing/Mux','Pose',[1280 285 1285 355],'Inputs','3');
block(model,'Sinks/Scope','PoseScope',[1340 300 1410 340]);
wire(model,'DifferentialDrive/1','Pose/1');wire(model,'DifferentialDrive/2','Pose/2');
wire(model,'DifferentialDrive/3','Pose/3');wire(model,'Pose/1','PoseScope/1');
end

function make_open_loop(model)
block(model,'Sources/Constant','LeftInput',[110 100 195 135],'Value','uL','SampleTime','cfg.Ts');
block(model,'Sources/Constant','RightInput',[110 185 195 220],'Value','uR','SampleTime','cfg.Ts');
wire(model,'LeftInput/1','DifferentialDrive/1','left_command');
wire(model,'RightInput/1','DifferentialDrive/2','right_command');
logger(model,'LeftInput/1','uL_log',[370 95 475 125]);
logger(model,'RightInput/1','uR_log',[370 195 475 225]);
note(model,'WEEK 2 / OPEN LOOP\nDouble-click LeftInput and RightInput to change commands.\nDouble-click DifferentialDrive to inspect the native blocks.\nRun week2_open_loop_tests for quantitative validation.',[100 20]);
end

function make_closed_loop(model,cfg)
empty_subsystem(model,'VirtualSensors',[110 110 285 265]);
s=[model '/VirtualSensors'];
for k=1:3
    names={'x','y','theta'};
    block(s,'Ports & Subsystems/In1',names{k},[25 25+55*k 55 45+55*k],'Port',num2str(k));
end
values={'cfg.trackReflectance','cfg.meters_per_pixel_x','cfg.sensor_front_m','cfg.sensor_spacing_m','cfg.sensor_threshold'};
names={'TrackMap','PixelScale','FrontOffset','SensorSpacing','Threshold'};
for k=1:5
    block(s,'Sources/Constant',names{k},[115 225+65*k 210 255+65*k],'Value',values{k},'SampleTime','inf');
end
matlab_block(s,'ReadMap',[315 110 500 345],fullfile(cfg.root,'kernels','virtual_sensors.m'));
for k=1:3
    n={'x','y','theta'};wire(s,[n{k} '/1'],['ReadMap/' num2str(k)]);
end
for k=1:5,wire(s,[names{k} '/1'],['ReadMap/' num2str(k+3)]);end
names={'strength','binary','sensorX','sensorY'};
for k=1:4
    block(s,'Ports & Subsystems/Out1',names{k},[595 90+65*k 625 110+65*k],'Port',num2str(k));
    wire(s,['ReadMap/' num2str(k)],[names{k} '/1']);
end
note(s,'WEEK 3: S1 is LEFT, S8 is RIGHT.\nReadMap rotates/translates 8 sensor points and samples this image only.\nNo centerline or future trajectory is used by the controller.',[300 410]);
matlab_block(model,'LineError',[340 125 465 225],fullfile(cfg.root,'kernels','line_error.m'));
wire(model,'VirtualSensors/1','LineError/1');wire(model,'VirtualSensors/2','LineError/2');
empty_subsystem(model,'PDController',[505 110 680 265]);
make_controller([model '/PDController']);
wire(model,'LineError/1','PDController/1','raw_error');
wire(model,'LineError/2','PDController/2','line_detected');
empty_subsystem(model,'MotorCommands',[730 110 940 265]);
make_commands([model '/MotorCommands'],cfg);
wire(model,'PDController/1','MotorCommands/1','correction');
wire(model,'LineError/2','MotorCommands/2');
wire(model,'MotorCommands/1','DifferentialDrive/1','left_command');
wire(model,'MotorCommands/2','DifferentialDrive/2','right_command');
wire(model,'DifferentialDrive/1','VirtualSensors/1','x');
wire(model,'DifferentialDrive/2','VirtualSensors/2','y');
wire(model,'DifferentialDrive/3','VirtualSensors/3','theta');
logger(model,'VirtualSensors/1','strength',[130 330 230 360]);
logger(model,'VirtualSensors/2','sensors',[130 390 230 420]);
logger(model,'VirtualSensors/3','sensorX',[130 450 230 480]);
logger(model,'VirtualSensors/4','sensorY',[130 510 230 540]);
logger(model,'PDController/2','error',[360 330 460 360]);
logger(model,'PDController/3','P_term',[360 390 460 420]);
logger(model,'PDController/4','D_term',[360 450 460 480]);
logger(model,'MotorCommands/1','uL_log',[590 330 690 360]);
logger(model,'MotorCommands/2','uR_log',[590 390 690 420]);
logger(model,'MotorCommands/3','off_track',[590 450 690 480]);
logger(model,'LineError/2','detected',[590 510 690 540]);
block(model,'Signal Routing/Mux','ControlSignals',[820 345 825 455],'Inputs','4');
block(model,'Sinks/Scope','ControlScope',[880 370 955 425]);
wire(model,'PDController/2','ControlSignals/1');wire(model,'PDController/3','ControlSignals/2');
wire(model,'PDController/4','ControlSignals/3');wire(model,'PDController/1','ControlSignals/4');
wire(model,'ControlSignals/1','ControlScope/1');
block(model,'Sinks/Scope','SensorScope',[275 565 345 610]);wire(model,'VirtualSensors/2','SensorScope/1');
note(model,'WEEKS 3-4 / P AND PD CLOSED LOOP\nOpen each subsystem to learn the blocks. PDController contains native P/D/filter blocks.\nPositive error means line LEFT: uL=base-correction; uR=base+correction.\nDefault: Kp=0.45, Kd=0.03; Ki=0 (week 5). All values are SIMULATION data.',[100 15]);
end

function make_controller(s)
block(s,'Ports & Subsystems/In1','RawError',[20 55 50 75],'Port','1');
block(s,'Ports & Subsystems/In1','Detected',[20 120 50 140],'Port','2');
block(s,'Signal Routing/Switch','HoldDuringBriefLoss',[105 55 155 115],'Threshold','0.5','Criteria','u2 >= Threshold');
block(s,'Discrete/Unit Delay','PreviousError',[200 190 260 230],'SampleTime','cfg.Ts','InitialCondition','0');
wire(s,'RawError/1','HoldDuringBriefLoss/1');wire(s,'Detected/1','HoldDuringBriefLoss/2');
wire(s,'PreviousError/1','HoldDuringBriefLoss/3');wire(s,'HoldDuringBriefLoss/1','PreviousError/1');
block(s,'Math Operations/Gain','Kp',[245 30 315 65],'Gain','Kp');
block(s,'Math Operations/Sum','ErrorDifference',[245 95 280 135],'Inputs','+-');
block(s,'Math Operations/Gain','DivideByTs',[315 95 375 130],'Gain','1/cfg.Ts');
block(s,'Discrete/Discrete Transfer Fcn','DerivativeFilter',[415 90 535 135], ...
    'Numerator','[cfg.Ts/(cfg.derivative_tau+cfg.Ts) 0]', ...
    'Denominator','[1 -cfg.derivative_tau/(cfg.derivative_tau+cfg.Ts)]', ...
    'SampleTime','cfg.Ts','InitialStates','0');
block(s,'Math Operations/Gain','Kd',[575 95 640 130],'Gain','Kd');
block(s,'Math Operations/Sum','PplusD',[685 35 720 85],'Inputs','++');
wire(s,'HoldDuringBriefLoss/1','Kp/1');wire(s,'HoldDuringBriefLoss/1','ErrorDifference/1');
wire(s,'PreviousError/1','ErrorDifference/2');wire(s,'ErrorDifference/1','DivideByTs/1');
wire(s,'DivideByTs/1','DerivativeFilter/1');wire(s,'DerivativeFilter/1','Kd/1');
wire(s,'Kp/1','PplusD/1');wire(s,'Kd/1','PplusD/2');
names={'correction','held_error','P_term','D_term'}; sources={'PplusD/1','HoldDuringBriefLoss/1','Kp/1','Kd/1'};
for k=1:4
    block(s,'Ports & Subsystems/Out1',names{k},[800 20+60*k 830 40+60*k],'Port',num2str(k));
    wire(s,sources{k},[names{k} '/1']);
end
note(s,'WEEK 4: set Kd=0 for P; use Kd>0 for PD.\nFiltered derivative: d[k]=alpha*(e[k]-e[k-1])/Ts+(1-alpha)*d[k-1].\nInitial error/filter states reset on every fresh simulation.',[160 310]);
end

function make_commands(s,cfg)
block(s,'Ports & Subsystems/In1','Correction',[20 55 50 75],'Port','1');
block(s,'Ports & Subsystems/In1','Detected',[20 165 50 185],'Port','2');
block(s,'Sources/Constant','BaseCommand',[95 10 160 40],'Value','cfg.base_speed','SampleTime','cfg.Ts');
block(s,'Math Operations/Sum','LeftBaseMinusC',[215 40 245 80],'Inputs','+-');
block(s,'Math Operations/Sum','RightBasePlusC',[215 110 245 150],'Inputs','++');
block(s,'Discontinuities/Saturation','LeftLimit',[290 40 355 80],'UpperLimit','1','LowerLimit','0');
block(s,'Discontinuities/Saturation','RightLimit',[290 110 355 150],'UpperLimit','1','LowerLimit','0');
matlab_block(s,'LossGuard',[100 225 245 310],fullfile(cfg.root,'kernels','loss_guard.m'));
block(s,'Sources/Constant','Ts',[20 260 65 285],'Value','cfg.Ts','SampleTime','inf');
block(s,'Sources/Constant','Timeout',[20 315 75 340],'Value','cfg.loss_timeout_s','SampleTime','inf');
wire(s,'Detected/1','LossGuard/1');wire(s,'Ts/1','LossGuard/2');wire(s,'Timeout/1','LossGuard/3');
block(s,'Math Operations/Product','LeftEnable',[420 40 455 80],'Inputs','2');
block(s,'Math Operations/Product','RightEnable',[420 110 455 150],'Inputs','2');
wire(s,'BaseCommand/1','LeftBaseMinusC/1');wire(s,'Correction/1','LeftBaseMinusC/2');
wire(s,'BaseCommand/1','RightBasePlusC/1');wire(s,'Correction/1','RightBasePlusC/2');
wire(s,'LeftBaseMinusC/1','LeftLimit/1');wire(s,'RightBasePlusC/1','RightLimit/1');
wire(s,'LeftLimit/1','LeftEnable/1');wire(s,'LossGuard/1','LeftEnable/2');
wire(s,'RightLimit/1','RightEnable/1');wire(s,'LossGuard/1','RightEnable/2');
names={'left_command','right_command','off_track'};sources={'LeftEnable/1','RightEnable/1','LossGuard/2'};
for k=1:3
    block(s,'Ports & Subsystems/Out1',names{k},[540 5+65*k 570 25+65*k],'Port',num2str(k));
    wire(s,sources{k},[names{k} '/1']);
end
block(s,'Sinks/Terminator','UnusedMissingSeconds',[305 280 325 300]);wire(s,'LossGuard/3','UnusedMissingSeconds/1');
note(s,'Commands limited to [0,1]. Loss for 0.20 s latches stop.\nThis small guard supports week-4 experiments; full safety/reset UI is week 5.',[100 390]);
end
