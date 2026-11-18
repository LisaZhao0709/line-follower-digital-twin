function directory=twin_latest(week)
cfg=twin_config();p=fullfile(cfg.results_dir,sprintf('week%d_latest.txt',week));
assert(isfile(p),'Run week%d validation first.',week);
[~,n]=fileparts(strtrim(fileread(p)));directory=fullfile(cfg.results_dir,n);
assert(isfolder(directory),'Missing validation folder: %s',directory);
end
