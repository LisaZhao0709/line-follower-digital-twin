function play_reviewed_run(speed)
% Animate the frozen reviewed trace with its OWN saved map and geometry.
if nargin<1,speed=5;end
directory=latest_review_directory();
saved=load(fullfile(directory,'Exact_PD_20ms_run.mat'),'out','cfg');
play_run(saved.out,speed,saved.cfg);
end
