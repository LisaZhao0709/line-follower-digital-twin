function sync_loss_guard()
% Correct the saved original teaching model as well as newly cloned Exact models.
cfg=project_config();model='LF_Week4_PD';file=fullfile(cfg.models_dir,[model '.slx']);
load_system(file);assert(strcmp(get_param(model,'Dirty'),'off'),'Save edits before kernel synchronization.');
guard=get_param([model '/MotorCommands/LossGuard'],'MATLABFunctionConfiguration');
source=fileread(fullfile(cfg.root,'kernels','loss_guard.m'));
if strcmp(guard.FunctionScript,source),return;end
backup=fullfile(cfg.models_dir,'backups');if ~isfolder(backup),mkdir(backup);end
copyfile(file,fullfile(backup,[model '_before_timer_fix_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.slx']));
guard.FunctionScript=source;save_system(model,file);
fprintf('Synchronized corrected 0.20-second loss timer into %s\n',model);
end
