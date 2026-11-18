function app=twin_app(visible)
% Student changes only Kp/Ki/Kd. Simulation first, then faithful recorded playback.
% Pause/step controls playback; every new simulation resets all controller states.
if nargin<1,visible='on';end
cfg=twin_config();base=twin_latest(5);S=load(fullfile(base,'PID_default_run.mat'),'cfg','record');
trace=readtable(fullfile(base,'PID_default_trace.csv'));cfg=S.cfg;cfg.root=fileparts(mfilename('fullpath'));
fig=figure('Name','Line-Follower PID Lab','NumberTitle','off','Color',[.96 .97 .99], ...
 'Position',[70 60 1220 790],'Visible',visible,'MenuBar','none','ToolBar','none','CloseRequestFcn',@closeApp);
axMap=axes('Parent',fig,'Position',[.055 .49 .55 .46]);
image(axMap,'XData',[0 cfg.map_width_m],'YData',[cfg.map_height_m 0], ...
 'CData',repmat(1-double(cfg.trackMask),1,1,3));set(axMap,'YDir','normal');axis(axMap,'equal');
xlim(axMap,[0 cfg.map_width_m]);ylim(axMap,[0 cfg.map_height_m]);hold(axMap,'on');
ylabel(axMap,'y (m)');title(axMap,'Recorded vehicle trajectory (x/y in metres)');
path=plot(axMap,NaN,NaN,'Color',[.85 .13 .15],'LineWidth',1.3);
body=patch(axMap,NaN,NaN,[.12 .43 .82],'FaceAlpha',.55);
sensorDots=scatter(axMap,NaN(1,8),NaN(1,8),28,'filled','MarkerEdgeColor',[.2 .2 .2]);
label('PID and environment',[.65 .915 .29 .04],14);
fields=gobjects(1,3);n={'Kp','Ki','Kd'};
for k=1:3
    label(n{k},[.65 .86-(k-1)*.065 .055 .04],12);
    fields(k)=uicontrol(fig,'Style','edit','Units','normalized','Position',[.71 .86-(k-1)*.065 .10 .045], ...
      'String',num2str(cfg.(n{k})),'FontSize',12,'BackgroundColor','white','Tag',n{k});
end
label({'Kp 0–20；Ki 0–2','Kd 0–0.5'},[.82 .845 .16 .055],10);
environmentControl=uicontrol(fig,'Style','popupmenu','Units','normalized','Position',[.82 .785 .16 .045], ...
    'String',{'Ideal environment','Mild light/shadow/vibration','Strong light/shadow/vibration'},'Value',1,'FontSize',10,'Tag','environment_level');
label('Seed',[.82 .735 .05 .04],10);
seedControl=uicontrol(fig,'Style','edit','Units','normalized','Position',[.88 .735 .10 .04], ...
    'String','7','BackgroundColor','white','FontSize',10,'Tag','environment_seed');
label('Environment and seed apply to the next run.',[.65 .70 .33 .025],9);
runButton=button('New experiment',[.65 .65 .14 .055],@runExperiment);
playButton=button('Play',[.81 .65 .075 .055],@play);
pauseButton=button('Pause',[.89 .65 .075 .055],@pausePlayback);
stepButton=button('Step',[.65 .58 .14 .055],@step);
resetButton=button('Reset',[.81 .58 .155 .055],@reset);
lamps=gobjects(1,8);
for k=1:8
    lamps(k)=uicontrol(fig,'Style','text','Units','normalized','Position',[.65+(k-1)*.04 .52 .035 .04], ...
      'String',sprintf('S%d',k),'FontSize',10,'BackgroundColor',[.88 .89 .90]);
end
statusBox=label('',[.65 .39 .315 .125],11);instantBox=label('',[.65 .265 .315 .12],10);
summaryBox=label('',[.65 .06 .315 .19],10);
axGray=axes('Parent',fig,'Position',[.055 .385 .545 .05]);
hold(axGray,'on');idealGray=plot(axGray,1:8,zeros(1,8),'--','Color',[.5 .5 .5]);
observedGray=plot(axGray,1:8,zeros(1,8),'-o','Color',[.1 .4 .8]);
xlim(axGray,[1 8]);ylim(axGray,[0 1]);grid(axGray,'on');
title(axGray,'Eight sensors: gray reference, blue observation');
axE=axes('Parent',fig,'Position',[.055 .095 .165 .25]);lineE=plot(axE,NaN,NaN,'Color',[.85 .13 .15]);grid(axE,'on');title(axE,'Tracking error');ylim(axE,[-1 1]);xlabel(axE,'t (s)');
axPID=axes('Parent',fig,'Position',[.265 .095 .165 .25]);hold(axPID,'on');
pidLines=gobjects(1,3);colors=[.1 .35 .8;.1 .6 .3;.9 .45 .05];
for k=1:3,pidLines(k)=plot(axPID,NaN,NaN,'Color',colors(k,:));end
grid(axPID,'on');title(axPID,'P / I / D');xlabel(axPID,'t (s)');legend(axPID,{'P','I','D'},'FontSize',8,'Location','best');
axMotor=axes('Parent',fig,'Position',[.475 .095 .125 .25]);hold(axMotor,'on');
motorLines=[plot(axMotor,NaN,NaN,'Color',[.1 .4 .8]),plot(axMotor,NaN,NaN,'Color',[.8 .3 .1])];
grid(axMotor,'on');title(axMotor,'Left/right motor commands');xlabel(axMotor,'t (s)');ylim(axMotor,[0 1]);
playTimer=timer('ExecutionMode','fixedSpacing','Period',.05,'BusyMode','drop','TimerFcn',@tick);
state=struct('trace',trace,'cfg',cfg,'record',S.record,'index',1,'playing',false,'busy',false,'directory',base,'error','');
guidata(fig,state);render();
app.figure=fig;app.fields=fields;app.run=runButton;app.play=playButton;app.pause=pauseButton;app.step=stepButton;app.reset=resetButton;
app.environment=environmentControl;app.seed=seedControl;
app.timer=playTimer;app.status=statusBox;app.axes=[axMap axE axPID axMotor axGray];
app.actions=struct('run',@()runExperiment([],[]),'play',@()play([],[]),'pause',@()pausePlayback([],[]), ...
 'step',@()step([],[]),'reset',@()reset([],[]),'close',@()closeApp([],[]));
    function h=label(text,pos,size)
        h=uicontrol(fig,'Style','text','Units','normalized','Position',pos,'String',text,'FontSize',size,'HorizontalAlignment','left','BackgroundColor',[.96 .97 .99],'FontName','Microsoft YaHei');
    end
    function h=button(text,pos,callback)
        h=uicontrol(fig,'Style','pushbutton','Units','normalized','Position',pos,'String',text,'FontSize',11,'FontName','Microsoft YaHei','Callback',callback);
    end
    function pausePlayback(~,~)
        if isvalid(playTimer) && strcmp(playTimer.Running,'on'),stop(playTimer);end
        q=guidata(fig);q.playing=false;guidata(fig,q);
    end
    function play(~,~)
        q=guidata(fig);if q.busy || q.index>=finishIndex(q),return;end
        q.playing=true;guidata(fig,q);if strcmp(playTimer.Running,'off'),start(playTimer);end
    end
    function step(~,~)
        pausePlayback([],[]);q=guidata(fig);if q.busy,return;end
        q.index=min(q.index+1,finishIndex(q));guidata(fig,q);render();
    end
    function reset(~,~)
        pausePlayback([],[]);q=guidata(fig);if q.busy,return;end
        q.index=1;q.error='';guidata(fig,q);render();
    end
    function tick(~,~)
        if ~isgraphics(fig),return;end
        q=guidata(fig);q.index=min(q.index+max(1,round(.2/q.cfg.Ts)),finishIndex(q));guidata(fig,q);render();
        if q.index>=finishIndex(q),pausePlayback([],[]);end
    end
    function n=finishIndex(q)
        n=q.record.analysis_end_index; % stop the displayed experiment at its lap/fault
    end
    function runExperiment(~,~)
        pausePlayback([],[]);q=guidata(fig);if q.busy,return;end
        try
            gains=arrayfun(@(h)str2double(h.String),fields);
            extra=struct('environment_level',environmentControl.Value-1,'environment_seed',str2double(seedControl.String));
            check=extra;check.Kp=gains(1);check.Ki=gains(2);check.Kd=gains(3);twin_config(check);
        catch
            q.error='Invalid settings: check PID bounds; seed must be an integer from 0 to 4294967295.';guidata(fig,q);statusBox.String=q.error;return;
        end
        q.busy=true;q.error='';guidata(fig,q);set([runButton fields environmentControl seedControl],'Enable','off');statusBox.String='Computing and validating the experiment…';drawnow;
        try
            [rec,tr,c,d]=run_twin_experiment(gains(1),gains(2),gains(3),extra);
            q=guidata(fig);q.trace=tr;q.cfg=c;q.record=rec;q.directory=d;q.index=1;q.error='';
            if isfield(q,'feedback'),q=rmfield(q,'feedback');end
        catch error
            q=guidata(fig);q.error=['Experiment failed: ' error.message];
        end
        q.busy=false;guidata(fig,q);set([runButton fields environmentControl seedControl],'Enable','on');render();
    end
    function render()
        q=guidata(fig);tr=q.trace;i=q.index;c=q.cfg;t=tr.time_s;
        path.XData=tr.x_m(1:i);path.YData=tr.y_m(1:i);
        local=[-c.body_length_m/2 -c.body_width_m/2;c.body_length_m/2 -c.body_width_m/2;c.body_length_m/2 c.body_width_m/2;-c.body_length_m/2 c.body_width_m/2];
        a=tr.theta_rad(i);world=local*[cos(a) sin(a);-sin(a) cos(a)]+[tr.x_m(i) tr.y_m(i)];body.XData=world(:,1);body.YData=world(:,2);
        sensorDots.XData=tr{i,arrayfun(@(k)sprintf('sensorX%d_m',k),1:8,'UniformOutput',false)};
        sensorDots.YData=tr{i,arrayfun(@(k)sprintf('sensorY%d_m',k),1:8,'UniformOutput',false)};
        sensors=tr{i,arrayfun(@(k)sprintf('S%d',k),1:8,'UniformOutput',false)};
        observedGray.YData=tr{i,arrayfun(@(k)sprintf('strength%d',k),1:8,'UniformOutput',false)};
        if ismember('ideal_strength1',tr.Properties.VariableNames)
            idealGray.YData=tr{i,arrayfun(@(k)sprintf('ideal_strength%d',k),1:8,'UniformOutput',false)};
        else
            idealGray.YData=observedGray.YData;
        end
        sensorDots.CData=[.2+.65*(1-sensors(:)) .25+.50*sensors(:) .3+.45*(1-sensors(:))];
        for j=1:8,lamps(j).BackgroundColor=sensorDots.CData(j,:);end
        lineE.XData=t(1:i);lineE.YData=tr.sensor_error(1:i);
        terms={'P_term','I_term','D_term'};for j=1:3,pidLines(j).XData=t(1:i);pidLines(j).YData=tr.(terms{j})(1:i);end
        motorLines(1).XData=t(1:i);motorLines(1).YData=tr.uL(1:i);motorLines(2).XData=t(1:i);motorLines(2).YData=tr.uR(1:i);
        for ax=[axE axPID axMotor],xlim(ax,[0 max(1,t(finishIndex(q)))]);end
        if ~isempty(q.error),statusBox.String=q.error;
        elseif exist('twin_feedback','file')==2
            if ~isfield(q,'feedback') || height(q.feedback)~=height(tr) || q.feedback.Kp_tag(1)~=c.Kp || q.feedback.Ki_tag(1)~=c.Ki || q.feedback.Kd_tag(1)~=c.Kd
                q.feedback=twin_feedback(tr,c);guidata(fig,q);
            end
            statusBox.String=sprintf('t = %.2f s | %s\n%s',t(i),q.feedback.status(i),q.feedback.message(i));
        else
            statusBox.String=sprintf('t = %.2f s | %s\nSensors sample the map; wheel speeds are simulated.',t(i),basicStatus(tr.stop_reason(i)));
        end
        instantBox.String=sprintf('Error %.3f | P %.3f | I %.3f | D %.3f\nCommands L %.3f / R %.3f\nSimulated speeds L %.3f / R %.3f m/s\nNominal residuals L %.4f / R %.4f m/s',tr.sensor_error(i),tr.P_term(i),tr.I_term(i),tr.D_term(i),tr.uL(i),tr.uR(i),tr.left_speed_mps(i),tr.right_speed_mps(i),tr.left_residual_mps(i),tr.right_residual_mps(i));
        if q.record.completed_lap,result=sprintf('Lap completed: %.2f s',q.record.lap_time_s);else,result='Lap not completed';end
        environmentText='Current record: ideal environment';
        if isfield(c,'environment_level') && c.environment_level>0
            environmentText=sprintf('Current record: environment %d, seed %u',c.environment_level,c.environment_seed);
        end
        summaryBox.String=sprintf('%s\n%s\nMAE for valid detections: %.4f\nMotor saturation: %.2f%%\nUse the same environment and seed to compare PID.\nReset rewinds playback; Run recomputes the experiment.',result,environmentText,q.record.mae,100*q.record.saturation_fraction);
        drawnow limitrate;
    end
    function closeApp(~,~)
        if isvalid(playTimer),stop(playTimer);delete(playTimer);end
        if isgraphics(fig),delete(fig);end
    end
end
function s=basicStatus(reason)
names={'Running','Line-loss stop','Out-of-bounds stop','Numerical safety stop','Simulation time limit'};s=names{reason+1};
end
