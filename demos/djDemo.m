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

% Construc the kSlurm object. Workers never need more than 10 minutes for
% the work this script sends them
c = kSlurm('Minutes',10,...
            'StartupFolder','/home/bart/Documents/MATLAB', ...
            'EnvironmentVariables',env, ...
            'AdditionalPaths',additionalPaths, ...
            'Debug',true);

c.gitFolders = gitFoldersOnAmarel;
gpo(c);  % git pull origin (this assumes there are no changes on the cluster. An warning will be given otherwise.

% For DJ to work, we have to be in the code folder of the project repo that
% has the +ns/getSchema
c.batchDefaults.CurrentFolder = '/home/bart/mousetDCS/code';


%%
% Now some real datajoint code.
% Locally I'd populate the sbx.Tuning table with:
% populate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')
% To speed things up we can use the built-in DataJoint function parpopulate
% and let that run on a pool of workers:
% In principle that should work like this:
if false
nrWorkers = 10;
parfevalOnAll(c,@parpopulate,0,{sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%'''},'Pool',nrWorkers)
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

% parforOpts will request as many workers as available in the c object.
% ('Pool' argument does not work, nor does 'MaxNumWorkers'). So limit in c:
c.NumWorkers = 10;
opts =parforOpts(c);
parfor (i=1:nrWorkers,opts)
    cd '/home/bart/mousetDCS/code' % parfor client mode does not use .CurrentFolder force it 
    parpopulate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''');
end
c.NumWorkers =128; % Set it back to the original maximum.


% This parfor blocks the client until all tables have been filled. So an
% alternative batch mode versionof this  captures the command we want to
% exectute as an expression in a string and then uses the script interface
% to send it to the workers.
expression = "parpopulate(sbx.Tuning,'pcell>0.99','paradigm like ''%ORI%''')";

job = script(c,expression,'Pool',nrWorkers); 
% This code will finish as soon as the workers have started and then the
% client is ready for use again. For the demo, we wait to show the results.
wait(job);
% There are no output arguments to fetch/load; all output is written to the
% SQL database by DataJoint. But we can look at the command line output:
job.diary
% or at the Tasks  (one task is the "parent" who starts 2 workers )
job.Tasks 
% And the Task may have some information on what happened:
job.Tasks(1) % The parent task
job.Tasks(2) % A worker

 




