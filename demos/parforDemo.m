%% Example 3 - Parfor Locally, with execution on the Cluster
% You have an analysis pipepline that uses a parfor. To speed things up you'd like to
% run this on as many workers as possible and therefore use the cluster.
%
% One option is to send the top-level script or function to tje cluster to
% compute everything on the cluster and then retrieve the information once
% it is done.  See batchDemo for that scenario.
% 
% The alternative shown here to run the top level script/function (the one with the
% parfor) locally, but tell the parfor loop to use processes on the cluster
% using a ClusterOptions object.
%
% The main difference with batchDemo is that at the end of the loop, the
% result (A) is in the current workspace and we do not have to use load or
% fetchOutputs to retrieve the results from the cluster.
% 
% The main disadvantage is that Matlab on your client will stall during the
% parfor loop.
%
% One advantage is that you can write your code and debug it
% on your local machine by using a ClsuterOptions object based on the local
% cluster and once everything works and you;re ready to run a big analysis,
% you can simply specify a cluster-based opts instead. Assuming that the
% cluster has access to the same code (and data files) that should then
% work seamlessly.
% 
% See also kSlurm.parforOpts , parforOptions

% Setup the object 
c=kSlurm('NumWorkers',10,'Hours',0,'Minutes',20);

% Request a ClusterOptions object from the kSlurm  object.
% Use the options function to include some of the kSlurm defaults.
% In principle parforOptions(c) works too.
opts = parforOpts(c);  % This will request all available workers in 'c'. (Testing suggests it may request more...?)

% Now we can write a parfor that uses those workers
% This is a blocking call and will finish once all iterations are complete

% Note: if you forget the () brackets, the opts will not be used and the
% computation will run locally. You can tell by how quickly it completes
% and that the opts object is written to the command line. 
parfor (i = 1:1024, opts)  
  A(i) = sin(i*2*pi/1024);
end
plot(A)




