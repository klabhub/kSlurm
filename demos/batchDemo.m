%% Example 1 - Running a script with parfor on a cluster.
% You have an analysis pipepline that uses a parfor. To speed things up you'd like to
% run this on as many workers as possible and therefore use a cluster.
%
% If the starting point for the analysis is a script, use kSlurm.script (Example 1),
% if it is a function, use kSlurm.fun 
%
% Here a script (wave.m) uses a parfor to fill a variable 'A'.
% We are going to run this parfor on 10 workers on the cluster.
%
% This assumes that you have alread set your preferences as explained in
% the tutorial.mlx.
%
% Setup a kSlurm object that allows 20 minutes of prcessing on 11 workers (we need 1
% more worker than members of the parpool). I am asking for 20 minutes just
% to be safe.
c=kSlurm('NumWorkers',11,'Hours',0,'Minutes',20);
% Use the script function to run the wave script on a parpool of 10 workers
% Note that the wave script is autoamtically copied to the cluster.
job = script(c,'wave','Pool',10);
% (The same can be achieved with batch(c,...) but it would require setting
% a few extra arguments to avoid copying too much to the cluster.)
%
% This function call returns once the workers are running on the cluster. That
% can take a few minutes.
%
% After the job has been submitted, you can get a summary of the job by typing
% job on the command line. You can refresh this by typing job again,
% or use the job monitor  (Click Parallel | Monitor Jobs in the Matlab Ribbon)
% to see what is running on the cluster. For that to work, though , you have to
% first save the kSlurm object as a profile
% (saveAsProfile(c,'profileName').) Note that each setting (e.g., wall
% time) will need to be stored as a separate profile. Some naming scheme
% would be helpful to keep track of these.  
%
% In my epxerience the 'Pending' status is not always accurate, and the
% updates are very slow. Running squeue or sacct on the cluster command line
% may give a more up to date info. For instance:
%
% Run a command remotely , on the cluster
runCommand(c,sprintf('sacct -j %s',job.Tasks(1).SchedulerID))
% or
runCommand(c,sprintf('squeue -n %s', c.AdditionalProperties.Username))

% For now, let's wait for the job to complete
wait(job)
% Once the job has completed , you can retrieve the results
% Because 'wave' is a script, we get the result (the 'A" variable used in
% the wave script with the load command.
load(job,'A') % This will load the 'A" variable created in the wave.m script
plot(A); % Each point in the sine was computed by a different process...

%Had you used a fun(c) to speed up a parfor in a function instead of a script
%then you'd use
%results =fetchOutputs(job)
