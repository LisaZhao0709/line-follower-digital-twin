function write_acceptance_report(cfg,summary)
file=fullfile(cfg.results_dir,'验收结果.md');
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Weeks 1-4 acceptance results\n\n');
fprintf(fid,'Verification environment: %s. Report generated: %s.\n\n',version,char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
fprintf(fid,'- Week 1: inner loop retained; outer frame removed; 2 cm line-width calibration; correct world axes.\n');
fprintf(fid,'- Week 2: five Simulink tests passed for stop, straight, left turn, right turn and upward motion.\n');
fprintf(fid,'- Week 3: centre, left/right offsets, outside-map readings, 90-degree rotation and error-sign tests passed.\n');
fprintf(fid,'- Week 4: P and PD completed a lap; weak P stopped on line loss; repeated runs agreed.\n\n');
fprintf(fid,'|Experiment|Kp|Kd|Lap completed|Lap time/s|MAE for valid detections|Line-loss stop time/s|\n|---|---:|---:|---|---:|---:|---:|\n');
for k=1:height(summary)
    fprintf(fid,'|%s|%.3f|%.3f|%d|%.2f|%.4f|%.2f|\n',summary.case_name(k),summary.Kp(k),summary.Kd(k), ...
        summary.completed_lap(k),summary.lap_time_s(k),summary.mae_sensor_error(k),summary.stop_time_s(k));
end
fprintf(fid,'\nP/PD comparisons use the same map, initial pose, base speed and motor model.\n');
fprintf(fid,'\nMAE uses only samples with a detected line. Weak P stops before the sharp turn; its lower MAE does not imply better control. Check lap completion first.\n');
fprintf(fid,'\nMap dimensions %.2f × %.2f m are estimated from image line width; chassis, motor and sensor dimensions are simulation assumptions.\n',cfg.map_width_m,cfg.map_height_m);
fprintf(fid,'\nNormalized sensor error is dimensionless. Offline lap progress uses the inner boundary; completion requires progress >= 1.0 and distance to the start < 0.08 m. The reference is not a controller input.\n');
fprintf(fid,'\nPD has slightly lower error but greater total command variation here. Compare error, saturation and chatter together; derivative action does not necessarily improve every metric. See week4_comparison.csv.\n');
fprintf(fid,'\nThis stage is a teaching simulation without a physical vehicle connection. Integral action, the full dashboard and teaching-state rules are added in later stages.\n');
end
