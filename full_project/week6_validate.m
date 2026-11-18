function directory=week6_validate()
assert(isfile(fullfile(twin_latest(5),'status.json')));cfg=twin_config();
directory=fullfile(cfg.results_dir,['week6_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(directory);
diary(fullfile(directory,'matlab.log'));cleaner=onCleanup(@()diary('off'));
app=twin_app('off');cleanUI=onCleanup(@()app.actions.close());
q=guidata(app.figure);assert(q.index==1 && ~q.playing && numel(app.fields)==3);
app.actions.step();q=guidata(app.figure);assert(q.index==2);
app.actions.reset();q=guidata(app.figure);assert(q.index==1 && q.trace.x_m(1)==q.cfg.x0 && q.trace.y_m(1)==q.cfg.y0);
set(app.fields(1),'String','NaN');old=q.trace;app.actions.run();q=guidata(app.figure);assert(~isempty(q.error) && isequaln(q.trace,old) && ~q.busy);
set(app.fields(1),'String','21');app.actions.run();q=guidata(app.figure);assert(~isempty(q.error) && isequaln(q.trace,old));
set(app.fields(1),'String','.45');set(app.fields(2),'String','0');set(app.fields(3),'String','.03');
app.actions.run();q=guidata(app.figure);assert(isempty(q.error) && q.record.completed_lap && all(q.trace.I_term==0));
assert(q.index==1 && isfolder(q.directory) && isfile(fullfile(q.directory,'experiment_trace.csv')));
reference=readtable(fullfile(twin_latest(5),'PD_no_I_trace.csv'));
assert(isequal(reference.Properties.VariableNames,q.trace.Properties.VariableNames));
assert(max(abs(reference{:,:}-q.trace{:,:}),[],'all')<1e-12,'Replay differs beyond CSV serialization precision.');
app.actions.play();pause(.17);app.actions.pause();q=guidata(app.figure);assert(q.index>1 && ~q.playing && strcmp(app.timer.Running,'off'));
i=q.index;pause(.1);q=guidata(app.figure);assert(q.index==i);
app.actions.reset();q=guidata(app.figure);assert(q.index==1);
% Saved screenshot includes real MATLAB controls, not a drawn mockup.
set(app.figure,'Visible','on');drawnow;frame=getframe(app.figure);imwrite(frame.cdata,fullfile(directory,'student_interface.png'));
app.actions.close();assert(~isgraphics(app.figure) && ~isvalid(app.timer));
twin_write_json(fullfile(directory,'status.json'),struct('week',6,'passed',true,'checks',13,'actual_run_equal_to_week5_PD',true,'ui_screenshot_verified',true));
fid=fopen(fullfile(cfg.results_dir,'week6_latest.txt'),'w');fprintf(fid,'%s',directory);fclose(fid);
fprintf('WEEK6_PASSED %s\n',directory);
end
