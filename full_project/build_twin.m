function build_twin(force)
% Extend the previously verified native P/D + exact kinematics model.
if nargin<1,force=false;end
cfg=twin_config();addpath(cfg.root,fullfile(cfg.root,'kernels'));
target=fullfile(cfg.models_dir,'LineFollowerTwin.slx');model='LineFollowerTwin';
if isfile(target) && ~force
    load_system(target);
    c=get_param([model '/VirtualSensors/ReadMap'],'MATLABFunctionConfiguration');
    f=get_param([model '/VirtualSensors/SensorDisturbance'],'MATLABFunctionConfiguration');
    if strcmp(c.FunctionScript,fileread(fullfile(cfg.root,'kernels','virtual_sensors.m'))) ...
            && strcmp(f.FunctionScript,fileread(fullfile(cfg.root,'kernels','sensor_fault.m'))) ...
            && strcmp(get_param([model '/VirtualSensors/EnvironmentInput'],'OutputAfterFinalValue'),'Holding final value')
        return;
    end
end
if bdIsLoaded(model)
    assert(strcmp(get_param(model,'Dirty'),'off'),'Save model edits before rebuilding.');close_system(model,0);
end
if isfile(target)
    d=fullfile(cfg.models_dir,'backups');if ~isfolder(d),mkdir(d);end
    copyfile(target,fullfile(d,['LineFollowerTwin_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.slx']));
end
load_system('simulink');load_system(fullfile(cfg.models_dir,'Seed_PD_Exact.slx'));
save_system('Seed_PD_Exact',target);close_system('Seed_PD_Exact',0);load_system(target);
mw=get_param(model,'ModelWorkspace');assignin(mw,'cfg',cfg);
for n={'Kp','Ki','Kd'},assignin(mw,n{1},cfg.(n{1}));end
set_param([model '/PDController'],'Name','PIDController');s=[model '/PIDController'];
delete_line(s,'Kp/1','PplusD/1');delete_line(s,'Kd/1','PplusD/2');
set_param([s '/PplusD'],'Name','PplusIplusD','Inputs','+++');
fn(s,'IntegralAntiWindup',[390 330 595 480],'integral_aw.m');
constant(s,'Ki',[80 360 145 390],'Ki');constant(s,'TsI',[80 410 145 440],'cfg.Ts');
constant(s,'IntegralLimit',[80 460 175 490],'cfg.integral_limit');
constant(s,'BaseI',[80 510 165 540],'cfg.base_speed');constant(s,'AntiWindup',[80 560 165 590],'cfg.anti_windup');
src={'HoldDuringBriefLoss/1','Kp/1','Kd/1','Detected/1','Ki/1','TsI/1','IntegralLimit/1','BaseI/1','AntiWindup/1'};
for k=1:numel(src),wire(s,src{k},['IntegralAntiWindup/' num2str(k)]);end
wire(s,'Kp/1','PplusIplusD/1');wire(s,'IntegralAntiWindup/1','PplusIplusD/2');wire(s,'Kd/1','PplusIplusD/3');
out(s,'I_term',5,[800 335 830 355],'IntegralAntiWindup/1');
out(s,'anti_windup',6,[800 405 830 425],'IntegralAntiWindup/2');
% Native P, difference, derivative filter, and D branches remain editable.
notes=find_system(s,'FindAll','on','Type','annotation');delete(notes);
note(s,'WEEK 5: native P/D; bounded conditional integral output.\nKi=0 disables and resets I. Brief loss freezes I. A fresh run resets every state.',[225 650]);
% Precomputed seeded environmental input is sampled at the control rate.
s=[model '/VirtualSensors'];delete_line(s,'ReadMap/1','strength/1');delete_line(s,'ReadMap/2','binary/1');
c=get_param([s '/ReadMap'],'MATLABFunctionConfiguration');
c.FunctionScript=fileread(fullfile(cfg.root,'kernels','virtual_sensors.m'));
add_block('simulink/Sources/From Workspace',[s '/EnvironmentInput'], ...
    'Position',[20 780 205 815],'VariableName','cfg.environment_input','Interpolate','off', ...
    'SampleTime','cfg.Ts','OutputAfterFinalValue','Holding final value');
wire(s,'EnvironmentInput/1','ReadMap/9');
out(s,'ideal_strength',5,[810 760 840 780],'ReadMap/5');
out(s,'environment',6,[810 820 840 840],'EnvironmentInput/1');
fn(s,'SensorDisturbance',[570 390 775 535],'sensor_fault.m');
add_block('simulink/Sources/Digital Clock',[s '/SensorTime'],'Position',[280 525 360 550],'SampleTime','cfg.Ts');
constant(s,'DropoutStart',[275 590 390 620],'cfg.dropout_start_s');constant(s,'DropoutDuration',[275 645 405 675],'cfg.dropout_duration_s');
constant(s,'Noise',[275 700 405 730],'cfg.sensor_noise');
wire(s,'ReadMap/1','SensorDisturbance/1');wire(s,'SensorTime/1','SensorDisturbance/2');
wire(s,'DropoutStart/1','SensorDisturbance/3');wire(s,'DropoutDuration/1','SensorDisturbance/4');
wire(s,'Noise/1','SensorDisturbance/5');wire(s,'Threshold/1','SensorDisturbance/6');
wire(s,'EnvironmentInput/1','SensorDisturbance/7');
wire(s,'SensorDisturbance/1','strength/1');wire(s,'SensorDisturbance/2','binary/1');
add_block('simulink/Sinks/Terminator',[s '/UnusedCleanBinary'],'Position',[550 215 575 235]);wire(s,'ReadMap/2','UnusedCleanBinary/1');
logsignal(model,'VirtualSensors/5','ideal_strength',[130 750 245 780]);
logsignal(model,'VirtualSensors/6','environment',[130 810 245 840]);
% Replace the audited loss timer with a superset of safety checks.
s=[model '/MotorCommands'];conf=get_param([s '/LossGuard'],'MATLABFunctionConfiguration');
conf.FunctionScript=fileread(fullfile(cfg.root,'kernels','full_guard.m'));
for k=1:3
    n={'PoseX','PoseY','PoseTheta'};in(s,n{k},k+2,[20 380+55*k 50 400+55*k]);
    wire(s,[n{k} '/1'],['LossGuard/' num2str(k+3)]);
end
constant(s,'MapWidth',[110 510 235 540],'cfg.map_width_m');constant(s,'MapHeight',[110 570 235 600],'cfg.map_height_m');
add_block('simulink/Sources/Digital Clock',[s '/SafetyTime'],'Position',[115 630 195 660],'SampleTime','cfg.Ts');
constant(s,'Horizon',[110 690 235 720],'cfg.stop_time');
wire(s,'MapWidth/1','LossGuard/7');wire(s,'MapHeight/1','LossGuard/8');wire(s,'SafetyTime/1','LossGuard/9');wire(s,'Horizon/1','LossGuard/10');
% A switch returns literal zero even if an upstream signal is NaN (NaN*0 is NaN).
for side={'Left','Right'}
    n=side{1};delete_line(s,[n 'Limit/1'],[n 'Enable/1']);
    delete_line(s,'LossGuard/1',[n 'Enable/2']);delete_line(s,[n 'Enable/1'],[lower(n) '_command/1']);
    delete_block([s '/' n 'Enable']);
end
constant(s,'SafeZero',[295 355 350 385],'0');
for side={'Left','Right'}
    n=side{1};p=[420 40 465 90];if strcmp(n,'Right'),p=[420 110 465 160];end
    add_block('simulink/Signal Routing/Switch',[s '/' n 'Enable'],'Position',p,'Threshold','.5','Criteria','u2 >= Threshold');
    wire(s,[n 'Limit/1'],[n 'Enable/1']);wire(s,'LossGuard/1',[n 'Enable/2']);wire(s,'SafeZero/1',[n 'Enable/3']);
    wire(s,[n 'Enable/1'],[lower(n) '_command/1']);
end
out(s,'stop_reason',4,[540 275 570 295],'LossGuard/4');
out(s,'enabled',5,[540 340 570 360],'LossGuard/1');
for k=1:3,wire(model,['DifferentialDrive/' num2str(k)],['MotorCommands/' num2str(k+2)]);end
% Separate simulated wheel speeds, nominal expectations and residuals.
s=[model '/DifferentialDrive'];set_param([s '/LeftMotor'],'Gain','cfg.km*cfg.motor_left_factor');
set_param([s '/RightMotor'],'Gain','cfg.km*cfg.motor_right_factor');
out(s,'left_speed',4,[995 240 1025 260],'LeftMotor/1');out(s,'right_speed',5,[995 295 1025 315],'RightMotor/1');
add_block('simulink/Math Operations/Gain',[model '/ExpectedLeftSpeed'],'Position',[1000 585 1105 620],'Gain','cfg.km');
add_block('simulink/Math Operations/Gain',[model '/ExpectedRightSpeed'],'Position',[1000 650 1105 685],'Gain','cfg.km');
add_block('simulink/Math Operations/Sum',[model '/LeftResidual'],'Position',[1150 585 1185 625],'Inputs','+-');
add_block('simulink/Math Operations/Sum',[model '/RightResidual'],'Position',[1150 650 1185 690],'Inputs','+-');
wire(model,'MotorCommands/1','ExpectedLeftSpeed/1');wire(model,'MotorCommands/2','ExpectedRightSpeed/1');
wire(model,'DifferentialDrive/4','LeftResidual/1');wire(model,'ExpectedLeftSpeed/1','LeftResidual/2');
wire(model,'DifferentialDrive/5','RightResidual/1');wire(model,'ExpectedRightSpeed/1','RightResidual/2');
src={'PIDController/5','PIDController/6','PIDController/1','MotorCommands/4','MotorCommands/5', ...
 'DifferentialDrive/4','DifferentialDrive/5','ExpectedLeftSpeed/1','ExpectedRightSpeed/1','LeftResidual/1','RightResidual/1'};
n={'I_term','anti_windup','correction','stop_reason','enabled','left_speed','right_speed','expected_left_speed','expected_right_speed','left_residual','right_residual'};
for k=1:numel(n),logsignal(model,src{k},n{k},[1530 40+50*k 1660 70+50*k]);end
notes=find_system(model,'SearchDepth',1,'FindAll','on','Type','annotation');delete(notes);
note(model,'COMPLETE 8-WEEK PID TEACHING TWIN / R2025b\nStudent controls: Kp, Ki, Kd. Use START_PROJECT to open the classroom interface.\nActual simulation states; ideal no-slip model; geometry and motor speed require calibration.\nP/D and exact interval motion use native blocks. I and safety kernels are open source.',[110 15]);
save_system(model,target);fprintf('BUILT %s\n',target);
end
function wire(s,a,b),add_line(s,a,b,'autorouting','on');end
function constant(s,n,p,v),add_block('simulink/Sources/Constant',[s '/' n],'Position',p,'Value',v,'SampleTime','inf');end
function in(s,n,k,p),add_block('simulink/Ports & Subsystems/In1',[s '/' n],'Position',p,'Port',num2str(k));end
function out(s,n,k,p,src),add_block('simulink/Ports & Subsystems/Out1',[s '/' n],'Position',p,'Port',num2str(k));wire(s,src,[n '/1']);end
function fn(s,n,p,file)
add_block('simulink/User-Defined Functions/MATLAB Function',[s '/' n],'Position',p);
c=get_param([s '/' n],'MATLABFunctionConfiguration');c.FunctionScript=fileread(fullfile(fileparts(mfilename('fullpath')),'kernels',file));
end
function logsignal(s,src,n,p)
add_block('simulink/Sinks/To Workspace',[s '/Log_' n],'Position',p,'VariableName',n,'SaveFormat','Timeseries','MaxDataPoints','inf','SampleTime','-1');wire(s,src,['Log_' n '/1']);
end
function note(s,t,p),a=Simulink.Annotation(s,strrep(t,'\n',newline));a.Position=p;end
