% Noninteractive review entry with explicit diagnostic output.
root=fileparts(mfilename('fullpath'));addpath(root,fullfile(root,'kernels'));
set(groot,'defaultFigureVisible','off');
try
    reviewDirectory=run_detailed_review();
catch exception
    fid=fopen(fullfile(root,'results','review_batch_error.txt'),'w','n','UTF-8');
    fprintf(fid,'%s',getReport(exception,'extended','hyperlinks','off'));fclose(fid);
    rethrow(exception);
end
