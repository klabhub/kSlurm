% Some tests and demos of running a DataJoint pipeline using kSlurm.
% This depends on a lot of other code:
%  DataJoint-Neurostim : https://github.com/klabhub/datajoint-neurostim
%  poissyFit           : https://github.com/klabhub/poissyFit
%
% The variables djHost, djUser, djPass have to be set before calling any
% code here. 


% Setup the environment (on the worker) for DataJoint pipeline
% Because workers run  /home/bart/Documents/MATLAB/startup.m any setenv in
% there will overrule the environment variables set in the KSlurm object. 
env.NS_ROOT = '/projectsn/f_bart_1/kmouse/';
env.NSCONDA  = '/home/bart/miniconda3';
env.DJ_HOST = djHost;
env.DJ_USER = djUser;
env.DJ_PASS = djPass;

% Matlab search path
additionalPaths = {'/home/bart/datajoint-neurostim',...
                    '/home/bart/datajoint-neurostim/datajoint-matlab',...
                    '/home/bart/poissyFit',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/mym/distribution/mexa64',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/compareVersions',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/GHToolbox',...                    
                    };
% Folders I want to git pull origin before running anything on the cluster
% Usually this would be only a single project directory (at this debugging
% stage I am gpo-ing some others too, just to be sure.
gitFoldersOnAmarel = {'/home/bart/poissyFit',...
                        '/home/bart/mousetDCS',...
                        '/home/bart/datajoint-neurostim'};

% Construc the kSlurm object. Assuming that workers never need more than 
% x minutes for the work this script sends them.
% Setting the startup folder saves time on startup becasue I createad a much
% reduced pathdef in that folder (the default install has all of Matlab Toolboxes,
% plus simuliink)
% For DJ to work, we have to be in the code folder of the project repo that
% has the +ns/getSchema  ('CurrentFolder')
c = kSlurm('Minutes',60,...            
            'EnvironmentVariables',env, ...
            'AdditionalPaths',additionalPaths, ...
            'StartupFolder','/home/bart/Documents/MATLAB',...
            'CurrentFolder','/home/bart/mousetDCS/code');


%% Update git
c.gitFolders = gitFoldersOnAmarel;
gpo(c);  % git pull origin (this assumes there are no changes on the cluster. An warning will be given otherwise.



%%
% Now some real datajoint code.
% Locally I'd populate the sbx.Tuning table with:
% populate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')
% To speed things up we can use the built-in DataJoint function parpopulate
% and let that run on a pool of workers:
% In principle that could look  like this:
nrWorkers = 32;

if false
    parfevalOnAll(c,@parpopulate,0,{sbx.Tuning,'pcell>0.95','paradigm like ''%ORI%'''},'Pool',nrWorkers) %#ok<UNRCH> 
end
% However, this executes sbx.Tuning on the client  (where it may not be on
% the path, and where the environment could be different) and then copies
% that object to the workers. I doubt that can work (and tests suggests it
% doesn't). 
% 
% What we want instead is to evaulate sbx.Tuning on the worker. 
% This is done in client-mode with a parfor of 1:nrWorkers and nrWorkers in
% the pool. All workers will be running parpopulate until the sbx.Tuning
% table has been filled:

% Note that parforOpts will request as many workers as available in the c object.
% ('Pool' argument does not work, nor does 'MaxNumWorkers'). So we have to 
% set the limit in c. The default for kSlurm is 128, for the demo I reduce
% this:
c.NumWorkers = nrWorkers;
opts =parforOpts(c);
parfor (i=1:nrWorkers,opts)
    cd('/home/bart/mousetDCS/code'); % parfor client mode does not use .CurrentFolder force it 
    dj.config('databaseUse_tls',false); % Our database install does not use TLS (SSH Connection errors)
    parpopulate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''');    
end
c.NumWorkers =128; % Set it back to the original maximum.

% This parfor blocks the client until all tables have been filled. What's
% worse if the client is interrupted (or loses network access to the
% cluster) then the jobs will stop. 

% An alternative, batch mode, version of this  captures the command we want to
% exectute as an expression in a string and then uses the script interface
% to send it to the workers. (You could also put this in an
% actual m-file and send that to the workers with script(). Note that we do
% not need the 'cd; command in this case as script() automaticlly moves to
% the c.jobDefaults.CurrentFolder specified above.
% Note that in batch-mode, the code you send/execute has to have a parfor
% in there somewhere! (Otherwise the code will run on 1 worker, and the
% other workers will just sit idly waiting for work). 
nrWorkers = 127;
expression = "nrWorkers =127; parfor i=1:nrWorkers;dj.conn('165.230.79.13','root','simple',[],[],false);parpopulate(sbx.Tuning,'pcell>0.8','paradigm like ''%ORI%''');end";
job = script(c,expression,'Pool',nrWorkers); 
% This code will finish as soon as the workers have started and then the
% client is ready for use again. Even exiting the client will not stop the jobs on the cluster. 
%
% There are no output arguments to fetch/load; all output is written to the
% SQL database by DataJoint. But we can look at the command line output:
job.diary   %Because c.batchDefaults.CaptureDiiary =true
% or at the Tasks  (one task is the "parent" who starts 2 workers )
job.Tasks 
% And the Task may have some information on what happened:
job.Tasks(1) % The parent task
job.Tasks(2) % A worker




