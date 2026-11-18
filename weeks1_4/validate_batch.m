% Actual local MATLAB batch verification, with UTF-8 diagnostics on failure.
root=fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'kernels'));
set(groot,'defaultFigureVisible','off');
try
    build_models(true);
    run_acceptance();
catch exception
    fid=fopen(fullfile(root,'results','validation_error.txt'),'w','n','UTF-8');
    fprintf(fid,'%s',getReport(exception,'extended','hyperlinks','off'));fclose(fid);
    fprintf('VALIDATION_FAILED: %s\n',exception.identifier);
    rethrow(exception);
end
