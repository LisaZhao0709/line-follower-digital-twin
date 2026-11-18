function summary=review_open_loop(directory)
% Compare both actual Simulink plants with the continuous analytic constant-twist solution.
cfg=project_config();
models={'LF_Week2_OpenLoop','LF_Week2_OpenLoop_Exact'};
cases={'stop',0,0,0; 'straight',.5,.5,0; 'left_turn',.3,.6,0; ...
    'right_turn',.6,.3,0; 'upward',.5,.5,pi/2; 'spin',-.3,.3,0};
row=0;records=struct([]);
for m=1:2
    model=models{m};load_system(fullfile(cfg.models_dir,[model '.slx']));
    for k=1:size(cases,1)
        method='euler';if m==2,method='exact_zoh';end
        c=project_config(struct('x0',0,'y0',0,'theta0',cases{k,4},'stop_time',2,'integration_method',method));
        in=Simulink.SimulationInput(model);in=in.setVariable('cfg',c,'Workspace',model);
        in=in.setVariable('uL',cases{k,2},'Workspace',model);in=in.setVariable('uR',cases{k,3},'Workspace',model);
        in=in.setModelParameter('StopTime','2');out=sim(in);
        [t,x]=series_data(out,'x');[~,y]=series_data(out,'y');[~,th]=series_data(out,'theta');
        v=c.km*(cases{k,2}+cases{k,3})/2;w=c.km*(cases{k,3}-cases{k,2})/c.wheel_base_m;
        thetaExact=c.theta0+w*t;
        if abs(w)<1e-12
            xExact=v*t*cos(c.theta0);yExact=v*t*sin(c.theta0);
        else
            xExact=v/w*(sin(thetaExact)-sin(c.theta0));
            yExact=v/w*(cos(c.theta0)-cos(thetaExact));
        end
        positionError=hypot(x-xExact,y-yExact);angleError=abs(th-thetaExact);
        row=row+1;r.model=string(model);r.case_name=string(cases{k,1});r.integration=string(method);
        r.uL=cases{k,2};r.uR=cases{k,3};r.theta0_rad=c.theta0;r.duration_s=t(end);
        r.expected_x_end_m=xExact(end);r.actual_x_end_m=x(end);
        r.expected_y_end_m=yExact(end);r.actual_y_end_m=y(end);
        r.expected_theta_end_rad=thetaExact(end);r.actual_theta_end_rad=th(end);
        r.max_position_error_m=max(positionError);r.max_angle_error_rad=max(angleError);
        if m==2,tolerance=1e-12;else,tolerance=.004;end
        r.position_tolerance_m=tolerance;r.passed=r.max_position_error_m<tolerance && r.max_angle_error_rad<1e-12;
        assert(r.passed,'Analytic comparison failed: %s %s',model,cases{k,1});
        if row==1,records=r;else,records(row)=r;end
        trace=table(t,x,y,th,xExact,yExact,thetaExact,positionError);
        writetable(trace,fullfile(directory,sprintf('open_%s_%s.csv',method,cases{k,1})));
        fprintf('ANALYTIC %s/%s max error %.6g m\n',method,cases{k,1},max(positionError));
    end
end
summary=struct2table(records);writetable(summary,fullfile(directory,'analytic_open_loop.csv'));
end
