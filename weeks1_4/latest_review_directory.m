function directory=latest_review_directory()
% Resolve the last run relative to THIS project, including after extracting a ZIP.
cfg=project_config();pointer=fullfile(cfg.results_dir,'review_latest.txt');
assert(isfile(pointer),'No review yet. Run run_detailed_review first.');
stored=strtrim(fileread(pointer));[~,name]=fileparts(stored);
directory=fullfile(cfg.results_dir,name);
assert(isfolder(directory),'Review directory is missing: %s',directory);
end
