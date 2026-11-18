function RUN_ALL_WEEKS(pythonExecutable)
% Strict sequential gates. A failed week stops this run immediately.
root=fileparts(mfilename('fullpath'));addpath(root,fullfile(root,'kernels'));
if nargin<1
    pythonExecutable=getenv('TWIN_PYTHON');
    if isempty(pythonExecutable),pythonExecutable='D:\ide\Anaconda\python.exe';end
end
assert(isfile(pythonExecutable),'Set TWIN_PYTHON or pass the Python executable path.');
assert(~contains(pythonExecutable,'"') && ~contains(root,'"'),'Paths cannot contain quote characters.');
try
    week5_validate();week6_validate();week7_validate();week8_validate();
    [code,output]=system(sprintf('"%s" "%s"',pythonExecutable,fullfile(root,'tools','verify_complete_project.py')));
    fprintf('%s',output);assert(code==0,'Independent review failed.');
    [code,output]=system(sprintf('"%s" "%s"',pythonExecutable,fullfile(root,'tools','package_complete_project.py')));
    fprintf('%s',output);assert(code==0,'Packaging verification failed.');
    twin_write_json(fullfile(root,'results','pipeline_status.json'),struct('passed',true,'completed_weeks',1:8,'finished_at',char(datetime('now','TimeZone','Asia/Shanghai'))));
catch error
    twin_write_json(fullfile(root,'results','pipeline_status.json'),struct('passed',false,'error',error.message,'identifier',error.identifier));rethrow(error);
end
fprintf('ALL_EIGHT_WEEKS_COMPLETE\n');
end
