% Testing performance on datajoint pipeline
% The variables djHost, djUser, djPass have to be set before calling any
% code here. 

c = kSlurm('hours',1,'nrWorkers',10);
% Folders I want to git pull origin before running anything on the cluster
% Usually this would be only a single project directory (at this debugging
% stage I am gpo-ing some others too,m just to be sure.
gitFoldersOnAmarel = {'/home/bart/poissyFit','/home/bart/mousetDCS','/home/bart/matlab-parallel-amarel-plugin','/home/bart/Documents/github/datajoint-neurostim'};
c.gitFolders = gitFoldersOnAmarel;
gpo(c);  % git pull origin (this assumes there are no changes on the cluster. An warning will be given otherwise.

% For DJ to work, we have to be in the code folder of the project repo that
% has the +ns/getSchema
c.batchDefaults.CurrentFolder = '/home/bart/mousetDCS/code';

% DJ uses some environmnet variables. The Cluster object can copy those to
% the workers.  First set them here: 
% Set environment variables needed for datajoint/neurostim
root = '/projectsn/f_bart_1/kmouse/';  
setenv('NS_ROOT',root);
setenv('NS_CONDA','/home/bart/miniconda3')
setenv('DJ_HOST',djHost)
dj.config('databaseUse_tls',false);
setenv('DJ_USER',djUser)
setenv('DJ_PASS',djPass)
% Select which to send to the workers (this will be passed to the Cluster
% jobs below)

env.NS_ROOT = root;
env.NSCONDA  = '/home/bart/miniconda3';
env.DJ_HOST = djHost;
env.DJ_USER = djUser;
env.DJ_PASS =djPass;

% It is not always 100% clear to me where Matlab gets its path when started on
% the cluster. One strategy is to simply add relevant folders to the path,
% with the AdditionalPaths option (which can be added in the call to
% script, fun, or parforOptions)
additionalPaths = {'/home/bart/datajoint-neurostim',...
                    '/home/bart/datajoint-neurostim/datajoint-matlab',...
                    '/home/bart/poissyFit',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/mym/distribution/mexa64',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/compareVersions',...
                    '/home/bart/Documents/MATLAB/Add-Ons/Toolboxes/GHToolbox',...                    
                    };

% Tell parforOptions which files to attach (in this case the stateCheck
% file that we want to run remotely for debugging) and the additional
% folders to add to the Matlab search path on the cluster
c = kSlurm('hours',1,'nrWorkers',10,'startupFolder','/home/bart/Documents/MATLAB');
ops= parforOpts(c,'AttachedFiles','stateCheck','AdditionalPaths',additionalPaths);
% Start a loop (connecting to two workers) and run the stateCheck function.
% This is a good way to find out what is happening on the cluster.
clear info
parfor (i=1:2,ops)
    info(i)  = stateCheck
end
% One thing to note is that the working directory for this operation is not
% the .CurrentFolder set above. In other words, this version ignores that
% input argument. 

% Because the code inside the parfor is executed on the worker, this works:
clear info
parfor (i=1:2,ops)
    cd '/home/bart/mousetDCS/code';
    info(i)  = stateCheck
end

% The parforOpts interface does not have a way to set environment variables
% Let's see if it works if we do it analogous to the CurrentFolder above
clear info
parfor (i=1:2,ops)
    cd '/home/bart/mousetDCS/code';
    setenv('DJ_HOST','bladiebla');
    info(i)  = stateCheck
end
% Yes, that works


% Let's do the same using the 'fun' interface. (This relies on the
% environment variables being set on the client before calling this
% function). That is odd as it means you cannot have different envs. 
job = fun(c,@stateCheck,1,{},'AttachedFiles','stateCheck','AdditionalPaths',additionalPaths,'EnvironmentVariables',environmentVariables);
wait(job)
info =fetchOutputs(job);% Cell array with outputs
info = info{1}; % The info - only 1 because we did not specify 'Pool' in the call to fun.
info.pwd  % This one does match the .CurrentFolder and shows the correct DJ_HOST 


%%
% Now some real datajoint code.
% Locally I'd like to populate the sbx.Tuning table with:
% populate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')
% To speed things up we can use the built-in DataJoint function parpopulate
% and let that run on a pool of workers:
% Locall that would look like 
% f= parfevalOnAll(@parpopulate,0,sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%'''); 
% To run the same on the cluster, the script interface is probably easiest.
% The hardest part is to make sure that the script/expression to run on the
% workers is formatted correctly. Especially with arguments in quotes this
% can get hairy: use a string, not a char, then you can simply copy the
% code that runs locally and surround it by "".
% Another tricky thing is that Matlab will try to determine on the client
% whether this will run. In this example it will look for the populate()
% function, but it is not smart enough to determine that sbx.Tuning
nrWorkers = 10;
c = kSlurm('hours',1,'nrWorkers',nrWorkers, ...
        'environmentVariables', env);
expression = "populate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')";
job = script(c,expression   , ...
                    'AdditionalPaths',additionalPaths , ...
                    'Pool',nrWorkers-1); 
% Note that no 'AttachedFiles are necessary (everything is on the cluster
% already). This will execute the "script"  on 2 workers
wait(job);
% There are no output arguments to fetch/load; all output is written to the
% SQL database by DataJoint. But we can look at the command line output:
job.diary
% or at the Tasks  (one task is the "parent" who starts 2 workers )
job.Tasks 
% And the Task may have some information on what happened:
job.Tasks(1) % The parent task
job.Tasks(2) % A worker

%% Using the direct parfor-with-opts interface
ops= parforOpts(c,'AdditionalPaths',additionalPaths,'AttachedFiles',{'stateCheck'});
parfor (i=1:2,ops)
    cd '/home/bart/mousetDCS/code';
    root = '/projectsn/f_bart_1/kmouse/';  
    setenv('NS_ROOT',root);
    dj.conn(djHost,djUser,djPass, '', '', false)
    parpopulate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')
    info(i)  =stateCheck;
end
% Remarkably this works; sbx.Tuning is only evaluated on the cluster, and
% not here on the client. And note that the variables djHost etc. which are
% defined in the local workspace, are automatically copied to the workers.





