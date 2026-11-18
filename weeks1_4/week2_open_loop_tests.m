function summary = week2_open_loop_tests()
% Quantitative physical invariants in the real Simulink plant.
cfg=project_config();model='LF_Week2_OpenLoop';
load_system(fullfile(cfg.models_dir,[model '.slx']));
cases={'stop',0,0,0; 'straight',.5,.5,0; 'left_turn',.3,.6,0; ...
    'right_turn',.6,.3,0; 'upward',.5,.5,pi/2};
fig=figure('Name','Week 2: open-loop validation','Color','w','Position',[80 80 1050 600]);
tiledlayout(2,3);
rows=cell(size(cases,1),8);
for k=1:size(cases,1)
    name=cases{k,1};ul=cases{k,2};ur=cases{k,3};th0=cases{k,4};
    c=project_config(struct('x0',0,'y0',0,'theta0',th0,'stop_time',2));
    in=Simulink.SimulationInput(model);
    in=in.setVariable('cfg',c,'Workspace',model);
    in=in.setVariable('uL',ul,'Workspace',model);
    in=in.setVariable('uR',ur,'Workspace',model);
    in=in.setModelParameter('StopTime','2');out=sim(in);
    [t,x]=series_data(out,'x');[~,y]=series_data(out,'y');[~,theta]=series_data(out,'theta');
    v=c.km*(ul+ur)/2;omega=c.km*(ur-ul)/c.wheel_base_m;
    expectedTh=th0+omega*t(end);
    if abs(omega)<1e-12
        expectedX=v*t(end)*cos(th0);expectedY=v*t(end)*sin(th0);
    else
        expectedX=v/omega*(sin(expectedTh)-sin(th0));
        expectedY=v/omega*(-cos(expectedTh)+cos(th0));
    end
    posError=hypot(x(end)-expectedX,y(end)-expectedY);
    angleError=abs(theta(end)-expectedTh);
    assert(posError<0.004 && angleError<1e-9,'Open-loop test failed: %s',name);
    nexttile;plot(x,y,'b-','LineWidth',1.5);axis equal;grid on;
    hold on;plot(expectedX,expectedY,'ro');
    xlabel('x (m)');ylabel('y (m)');title(strrep(name,'_',' '));
    rows(k,:)={name,ul,ur,x(end),y(end),theta(end),posError,true};
    fprintf('Week2 %-10s PASS position error=%.6g m\n',name,posError);
end
summary=cell2table(rows,'VariableNames',{'case_name','uL','uR','x_end_m','y_end_m','theta_end_rad','position_error_m','passed'});
writetable(summary,fullfile(cfg.results_dir,'week2_open_loop_tests.csv'));
exportgraphics(fig,fullfile(cfg.results_dir,'figures','week2_open_loop.png'),'Resolution',150);
end
