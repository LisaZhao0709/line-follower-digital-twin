function export_model_diagrams()
cfg=project_config();
for model={'LF_Week2_OpenLoop','LF_Week4_PD'}
    load_system(fullfile(cfg.models_dir,[model{1} '.slx']));
end
systems={'LF_Week2_OpenLoop','LF_Week4_PD','LF_Week4_PD/DifferentialDrive','LF_Week4_PD/PDController'};
names={'week2_model','week4_model','week2_plant_blocks','week4_PD_blocks'};
for k=1:numel(systems)
    print(['-s' systems{k}],'-dpng','-r150',fullfile(cfg.results_dir,'figures',[names{k} '.png']));
end
end
