classdef kSlurm < parallel.cluster.Generic
    % Wrapper code around a cluster object for the SLURM scheduler to
    % simplify connecting and submitting jobs from a Windows client to a
    % SLURM cluster.
    %
    % BK - June 2023

    properties (Constant)
        PREFGRP = "kSlurm"  % Group that stores string preferences for kSlurm
        PREFS   = ["User","IdentityFile","Host","RemoteStorage","MatlabRoot"];
    end

    properties (SetAccess = public)
        batchDefaults % Defaults settings for batch mode jobs (fun,script, parfevalOnAll)
        jobDefaults   % Default settings for client (parfor) and batch mode jobs

        gitFolders  (1,:) cell = {} % Use by gpo to keep remote repositories up to date.
    end



    methods (Access=public)
        function log(c,jobNr)
            % Matlab mirrors a log file (containing command line output) created on the cluster 
            % to the local jobstorage area. This function opens that file in the editor
            % for inspection.
            arguments 
                c (1,1) kSlurm
                jobNr (1,1) double = c.Jobs(end).ID
            end
            fname = ['Job' num2str(jobNr)];
            if ispc
                os = 'windows';
            else
                os = 'unix';
            end
            logFile = fullfile(c.JobStorageLocation.(os),fname,[fname '.log']);
            if exist(logFile,'file')
                edit(logFile)
            else
                error('Could not find log file %s for job %d',logFile,jobNr);
            end

        end
        function reset(c)
            % Reset the SSH connection to the cluster. 
            rc= getRemoteConnection(c);
            rc.disconnect;
        end

        function sinfo(c,args)
            % Call sinfo on the cluster. Command line args can be specified
            arguments
                c (1,1) kSlurm
                args (1,:) {mustBeText} = '--format "%12P %.5a %.10l %.16F %m %20N"'
            end
            runCommand(c,['sinfo ' args]);
        end

        function sacct(c,args)
            % Call sacct on the cluster. Command line args can be specified
            % By default only RUNNING jobs for the current Username are
            % shown.Use args input to change this.
            arguments
                c (1,1) kSlurm
                args (1,:) {mustBeText} = sprintf('--user %s --state RUNNING', c.AdditionalProperties.Username);
            end
            runCommand(c,['sacct ' args]);
        end


        function seff(c,args)
            % Call seff on the first task of the last job to run on the cluster. Command line args can be specified
            arguments
                c (1,1) kSlurm
                args (1,:) {mustBeText} = c.Jobs(end).Tasks(1).SchedulerID
            end
            runCommand(c,['seff ' args]);
        end


        function [status,stdout] = runCommand(c,cmd)
            % Run any unix command (cmd) on the cluster head node.
            % OUTPUT
            % stdout = What was written to the command line
            % status = The exit code of the command
            rc = getRemoteConnection(c);
            try
                [a,b] = runCommand(rc,cmd);
            catch
                % Probably a stale connection
                rc.disconnect
                fprintf('Failed to run the remote command. Reconnecting. Please try again.')
                return;
            end 
            if nargout==0
                disp(b)
            elseif nargout >=1
                status =a;
            elseif nargout >=2
                stdout = b;
            end
        end

        function gpo(c)
            % Do a git pull origin on the c.gitFolders on the cluster.
            % Do this before running a batch to make sure your code is up
            % to date.
            rc = getRemoteConnection(c);
            if rc.IsConnected
                [~,cwd] =rc.runCommand("pwd");
                for i=1:numel(c.gitFolders)
                    [exitCode,stdout] =rc.runCommand(sprintf("test -d ''%s''",c.gitFolders{i}));
                    if exitCode ~=0
                        fprintf(2,"%s does not exist (%S). Could not gpo\n",c.gitFolders{i},stdout);
                    else
                        [exitCode,stdout] =rc.runCommand(sprintf("git --work-tree=%s --git-dir=%s/.git pull origin",c.gitFolders{i},c.gitFolders{i}));
                        if exitCode ~=0
                            fprintf(2,"gpo failed on %s  (%s).\n ",c.gitFolders{i},stdout);
                        end
                        fprintf(2,"%s: %s\n",c.gitFolders{i},stdout)
                    end
                end
                rc.runCommand(sprintf("cd ''%s''",cwd));
            else
                error('Not connected to the remote host?')
            end
        end

        function o= parforOpts(c,varargin)
            % Returns a ClusterOptions oject that can be used in parfor
            % loops to indicate that the code should run on the cluster.
            % This is needed because standard parpool does not work (the
            % nodes cannot communicate with the client) , by passing an
            % opts object, the parfor will submit each iteration to a
            % separate worker, without using parpool.
            %
            % Although the user could call parforOptions directly on the
            % kSlurm object, this function uses some of the defaults set in
            % the object.
            %
            % EXAMPLE
            % parfor (i=1:10, opts)
            %   dosomething
            % end
            % NOTE
            % All parameter value pairs that can be specified in the call
            % to parforOptions can be specified here too.
            %
            % The MaxNumWorkers parameter works only for alocal parpool. 
            % By default this function will limit to c.NumWorkers (i.e.
            % the limit in the kSlurm object), but you can change this by
            % specifying a 'Limit' 
            %
            % See also parforOptions
            arguments
                c (1,1) kSlurm
            end
            arguments (Repeating)
                varargin
            end
            if numel(varargin)>0
                ix = find(strcmp(varargin(1:2:end),'Limit'));
                if isempty(ix)
                    limit = c.NumWorkers;
                else
                    limit = varargin{ix+1};
                    varargin([ix ix+1]) =[];
                end
                varargin =cat(2,varargin,{'RangePartitionMethod','fixed','SubrangeSize',ceil(limit/c.NumWorkers)});                
            end
            % Now call the built-in parforOptions with the defaults
            % specified first
            o=  parforOptions(c,c.jobDefaults,varargin{:});
        end
        function job =script(c,file,varargin)
            % This wraps around batch in the Cluster object, but that
            % method is sealed so we have to give it a different name.
            % The main reason to overload this here is to make use of
            % default job settings sucha as CurrentFolder , and
            % AutoAttachFiles. In the git-based workflow used with this
            % class, files are never copied to the cluster (but updated by
            % git). Other than that this function works the same as the
            % regular batch and can be given the same input arguments.
            %
            % Note that 'EnvironmentVariables' passed here are just a list of
            % environment variable names ; they are evaluated at
            % the time of submission, on the client. This differs from the
            % EnvironmentVariables set at construction of the kSlurm
            % object; those contain the values.
            %
            % Retrieve the results of the script with load(job) once the
            % job completes.
            %
            %   See also parallel.Cluster.batch
            arguments
                c (1,1) kSlurm
                file (1,:) {mustBeA(file,{'function_handle','char','string'})}
            end
            arguments (Repeating)
                varargin
            end
            % By passing the jobDefaults first, and the varargin later,
            % the user can overrule the jobDefaults for a specific job
            defs = cat(2,namedargs2cell(c.batchDefaults),namedargs2cell(c.jobDefaults));
            job = kSlurmBatch(c,file,defs{:},varargin{:});
        end

        function job =fun(c,f,nout,args,varargin)
            % Analogous to script, now for functions.
            %
            % To retrieve the output of the parallel workers, use
            % fetchOutputs(job)
            %
            %   See also parallel.Cluster.batch  kSlurm.script
            arguments
                c (1,1) kSlurm
                f (1,1) {mustBeA(f,'function_handle')}    % Function to run on the cluster
                nout (1,1) double {mustBeGreaterThanOrEqual(nout,0),mustBeInteger}  % Number of output arguments for the function f
                args (1,:) cell = {}                    % Cell array with input arguments for the function f
            end
            arguments (Repeating)
                varargin    % Parameter value pairs for parralel.batch
            end
            % By passing the defaults first, and the varargin later,
            % the user can overrule the defaults for a specific job
            defs = cat(2,namedargs2cell(c.batchDefaults),namedargs2cell(c.jobDefaults));
            job = kSlurmBatch(c,f,nout,args,defs{:},varargin{:});
        end

        function p = pool(c,nrWorkers,varargin)
             arguments
                c (1,1) kSlurm        
                nrWorkers (1,1) {mustBePositive,mustBeInteger} = c.NumWorkers
              end
              arguments (Repeating)
                varargin
              end              
              p = parpool(c,nrWorkers,'AutoAddClientPath',c.jobDefaults.AutoAddClientPath,varargin{:});
        end
        function job = parfevalOnAll(c,f,nout,args,varargin)
            % Start a parpool of size 'Pool' on the cluster, and
            % use it to evaluate the function f that many times in
            % parallel.
            % INPUT
            % c - kSlurm object
            % f - Function to evaluate
            % nout = Number of outputs that the function generates
            % args = Cell array with the inputs to the function f.
            % vararging - Parm/Value pairs passed to parellel.batch
            %
            % OUTPUT
            % job = The job. Use fetchOutputs(job) to retrieve the results.
            %
            % NOTE
            %   Once the job finishes, retrieve the results with
            %   fetchOutputs(job)
            %
            % See also parallel.Cluster.parfevalOnAll
            arguments
                c (1,1) kSlurm
                f (1,1) {mustBeA(f,'function_handle')}   % Function to evaluate
                nout (1,1) double {mustBeGreaterThanOrEqual(nout,0),mustBeInteger} % Number of output args for f
                args (1,:) cell = {}                        % Input args passed to f
            end
            arguments (Repeating)
                varargin
            end
            job = fun(c,@kSlurm.pfoaWrapper,nout,cat(2,{f},{nout},args),varargin{:});
        end

        function c = kSlurm(user,identityFile,pk)
            % Constructor function. Creates a parallel.Cluster object that connects to the
            % cluster and sets resources.
            %
            % For installation instructions, see README.md in this
            % repository. Setting up your preferred
            % host, user, identityFile will save a lot of typing later.
            %
            % INPUT
            % user - Username on hte cluster [getpref('user')]
            % identityFile - Full path SSH Keyfile (without a passphrase) [getpref('identityFile')]
            %
            % Ohter input arguments are optional parameter/value pairs:
            % Hours      - The requested wall time hours    [0]
            % Muinutes   - The requested wall time minutes  [10]
            % NumThreads  - Number threads per worker      [1]
            % NumWorkers - The maximum number of workers that a job can request [128]
            % Host      - The host name or ip address of the cluster [getpref('host')]
            % RemoteStorage - The location where job files will be stored [getpref('remoteStorage']
            % MatlabRoot  - The Root of the Matlab installation on the cluster. [getpref('matlabRoot')]
            % SbatchOptions - A string with additional options to pass to
            % sbatch [""]. This is where you can specify memory request,
            % gpus etc. See the sbatch documentation for the list of input
            % arguments.
            % EnvironmentVariables - struct with environment variables.
            %                   Each struct field should contain the value
            %                   (a string) of the environment variables.
            %                   These envs will be used for all
            %                   workers/jobs. The fun/script/parforOpts
            %                   functions can specify additional
            %                   environment variables.
            % StartupFolder - Folder (on the cluster) where the
            % workers will start (using the -sd command line argument). Use
            % this to execute a startup.m file in that folder (for instance
            % to set the path).
            %
            % AdditionalPaths - Cell array with paths to add to the search
            %                   path for each job.
            %
            % Debug -  Set to true to run in debug mode [false]
            % SInfo - Set to false to skip the sinfo output.
            % OUTPUT
            % c -  The kSlurm Cluster object
            %
            % EXAMPLE
            % This can be called every session, with appropriate resource requests and
            % then used to create a parpool
            %  c = kSlurm('bart','path/to/file/bart_amareln_rsa','Hours',1)
            %
            % Or, you can save the output as a named cluster profile, which can then be selected from the Parallel
            % button in the Command Window in future sessions
            %  saveAsProfile(c,'1 hour')
            %
            arguments
                user  = kSlurm.getpref('User')
                identityFile = kSlurm.getpref('IdentityFile')
                pk.Hours (1,1) double {mustBeInteger, mustBeInRange(pk.Hours,0,24)} = 0
                pk.Minutes (1,1) double {mustBeInteger,mustBeInRange(pk.Minutes,0,60)} = 10
                pk.NumThreads (1,1) double {mustBeInteger,mustBeInRange(pk.NumThreads,1,64)} = 1
                pk.NumWorkers (1,1) double {mustBeInteger,mustBePositive} = 128
                pk.Host (1,1) string = kSlurm.getpref('Host');
                pk.RemoteStorage (1,1) string = kSlurm.getpref('RemoteStorage')
                pk.MatlabRoot (1,1) string = kSlurm.getpref('MatlabRoot')
                pk.SbatchOptions (1,1) string =""
                pk.EnvironmentVariables struct = struct([])
                pk.StartupFolder (1,1) string = ""
                pk.Debug (1,1) logical =false
                pk.SInfo (1,1) logical = true
                % jobDefaults
                 pk.AutoAttachFiles (1,1) logical  = false;
                 pk.AutoAddClientPath (1,1) logical = false;
                 pk.AdditionalPaths (1,:) cell = {}
             
                % BatchDefaults
                pk.CurrentFolder (1,1) string = "."
                pk.CaptureDiary (1,1) logical = true;
            end
            if pk.MatlabRoot==""
                clientVersion = ver('matlab').Release;
                clientVersion = clientVersion(2:end-1);
                pk.MatlabRoot = sprintf('/opt/sw/packages/MATLAB/%s',clientVersion);
            end

            jobName= [getenv('COMPUTERNAME') '-MCP']; % Named the job after the submitting machine
            localStorage = tempdir;

            %% Setup the cluster object
            c =c@parallel.cluster.Generic;
            c.JobStorageLocation = struct('windows',localStorage,'unix',pk.RemoteStorage);
            c.NumThreads = pk.NumThreads;
            c.NumWorkers = pk.NumWorkers;
            c.ClusterMatlabRoot = pk.MatlabRoot; % Has to match the client's matlab version
            c.OperatingSystem = 'unix';
            c.HasSharedFilesystem = false;
            c.PluginScriptsLocation = fileparts(mfilename('fullpath'));
            c.AdditionalProperties.ClusterHost = pk.Host;
            c.AdditionalProperties.RemoteJobStorageLocation =pk.RemoteStorage;
            c.AdditionalProperties.Username = user;
            c.AdditionalProperties.IdentityFile = identityFile;
            c.AdditionalProperties.IdentityFileHasPassphrase = false;
            c.AdditionalProperties.EnableDebug = pk.Debug;
            c.AdditionalProperties.AdditionalSubmitArgs = pk.SbatchOptions + sprintf("   -t %02d:%02d:00 --job-name %s",pk.Hours, pk.Minutes,jobName);

            % kSlurm specific additions - processedin the submitFcns
            c.UserData  =struct('EnvironmentVariables',pk.EnvironmentVariables, ...
                'StartupFolder',pk.StartupFolder);

            if any(cellfun(@isempty,{c.AdditionalProperties.ClusterHost,c.AdditionalProperties.Username,c.AdditionalProperties.IdentityFile}))
                error('Host, User, and IdentityFile must be specified. See kSlurm.setpref how to set this up');
            end

            % Storo batc h(Script/fun/parfevalOnAll) defaults
            c.batchDefaults.CurrentFolder  =pk.CurrentFolder;
            c.batchDefaults.CaptureDiary = pk.CaptureDiary;
            % Store defaults that apply to all jobs (including client 
            % parfor)
            c.jobDefaults.AdditionalPaths = pk.AdditionalPaths;
            c.jobDefaults.AutoAddClientPath = pk.AutoAddClientPath;
            c.jobDefaults.AutoAttachFiles = pk.AutoAttachFiles;

            if pk.SInfo
                % Try to connect and get some info on the cluster
                fprintf('Trying to connect to  %s ...\n',  c.AdditionalProperties.ClusterHost)
                fprintf('********************************\n')
                fprintf('Partition and Node information: \n')
                c.sinfo;
                fprintf('********************************\n')
            end
        end
        function delete(c)

            try
                rc = getRemoteConnection(c);
                rc.disconnect
            catch me %#ok<NASGU>

                %Remote host may no longer be available, Silent fail.
            end
        end
    end

    methods (Access=protected)
        
        function job = kSlurmBatch( obj, scriptName, varargin )
            %BATCH Run MATLAB script or function as batch job
            % This is a ncopy of the Mathworks batch function. It is needed
            % here to sidestep the issue in the Mathworks code that
            % AutoAttachFiles =false is ignored. This function only differs
            % from builtin parallel.cluster.batch by not including
            % batchHelper2 package (And thereby forcing the use of
            % batchHelper2 in the kSLurm repository).
            %
            %   j = BATCH(cluster, 'aScript') runs the script aScript.m on a worker
            %   using the identified cluster.  The function returns j, a handle to the
            %   job object that runs the script. The script file aScript.m is copied
            %   to the worker. If the cluster object's Profile property is not empty,
            %   the profile is applied to the job and task that run the script.
            %
            %   j = BATCH(cluster, fcn, N, {x1,..., xn}) runs the function specified by
            %   a function handle or function name, fcn, on a worker using the
            %   identified cluster.  The function returns j, a handle to the job object
            %   that runs the function. The function is evaluated with the given
            %   arguments, x1,...,xn, returning N output arguments.  The function file
            %   for fcn is copied to the worker.  If the cluster object's Profile
            %   property is not empty, the profile is applied to the job and task that
            %   run the function.
            %
            %   j = BATCH( ..., P1, V1, ..., Pn, Vn) allows additional parameter-value
            %   pairs that modify the behavior of the job.  These parameters can be
            %   used with both functions and scripts, unless otherwise indicated.  The
            %   accepted parameters are:
            %
            %   - 'Workspace' - A 1-by-1 struct to define the workspace on the worker
            %     just before the script is called. The field names of the struct
            %     define the names of the variables, and the field values are assigned
            %     to the workspace variables. By default this parameter has a field for
            %     every variable in the current workspace where batch is executed. This
            %     parameter can only be used with scripts.
            %
            %   - 'AdditionalPaths' - A string, character vector, string array, or cell array
            %     of character vectors that defines paths to be added to the workers' MATLAB path
            %     before the script or function is executed.
            %
            %   - 'AttachedFiles' - A string, character vector, string array, or cell array
            %     of character vectors.  Each entry in the list identifies either a file or a folder,
            %     which is transferred to the worker.
            %
            %   - 'CurrentFolder' - A string or character vector to indicate in what folder the
            %     script executes. There is no guarantee that this folder exists on the
            %     worker. The default value for this property is the current folder of
            %     MATLAB when the batch command is executed. If the value for this
            %     argument is '.', there is no change in folder before batch execution.
            %
            %   - 'CaptureDiary' - A boolean flag to indicate that diary output should be
            %     retrieved from the script execution or function call.  See the DIARY
            %     function for how to return this information to the client.  The
            %     default is true.
            %
            %   - 'Pool' - A nonnegative integer or a range specified as a 2-element
            %     vector of integers that defines the size of the parallel pool to use
            %     when running the job. If the value is a range, the resulting pool has
            %     size as large as possible in the range requested. This value
            %     overrides the NumWorkersRange specified in the profile. The default
            %     is 0, which causes the script or function to run on only the single
            %     worker without a pool.
            %
            %   - 'EnvironmentVariables' - A character vector, string, string array, or cell
            %     array of character vectors that defines the names of environment variables
            %     which will be copied from the client session to the workers.
            %
            %   Examples:
            %   % Run a batch script on a worker
            %   myCluster = parcluster; % creates the default cluster
            %   j = batch(myCluster, 'script1');
            %
            %   % Run a batch script, capturing the diary, adding a path to the workers
            %   % and transferring some required files.
            %   j = batch(myCluster, 'script1', ...
            %             'AdditionalPaths', '\\Shared\Project1\HelperFiles',...
            %             'AttachedFiles', {'script1helper1', 'script1helper2'});
            %   % Wait for the job to finish
            %   wait(j)
            %   % Display the diary
            %   diary(j)
            %   % Get the results of running the script in this workspace
            %   load(j)
            %
            %   % Run a batch script on a remote cluster using a pool of 8 workers:
            %   j = batch(myCluster, 'script1', 'Pool', 8);
            %
            %   % Run a batch function on a remote cluster that generates a 10-by-10
            %   % random matrix
            %   j = batch(myCluster, @rand, 1, {10, 10});
            %   % Wait for the job to finish
            %   wait(j)
            %   % Display the diary
            %   diary(j)
            %   % Get the results of running the job into a cell array
            %   r = fetchOutputs(j)
            %   % Get the generated random number from r
            %   r{1}
            %
            %   % Run some batch scripts and then use findJob to retrieve the jobs.
            %   batch(myCluster, 'script1');
            %   batch(myCluster, 'script2');
            %   batch(myCluster, 'script3');
            %   myBatchJobs = findJob(myCluster, 'Username', 'myUsername')
            %
            %   See also batch, parcluster, parallel.Cluster/parpool,
            %            parallel.Cluster/Jobs, parallel.Cluster/findJob,
            %            parallel.Job/wait, parallel.Job/load, parallel.Job/diary.

            % Copyright 2011-2018 The MathWorks, Inc.

            % BK : NOT importing this so that it uses the near-copy in the kSlurm repo: 
            % import parallel.internal.cluster.BatchHelper2
            % All other code is copied from parallel.cluster.batch
            import parallel.internal.apishared.ProfileConfigHelper

            % Convert any string inputs to character vectors
            [scriptName, varargin{:}] = convertStringsToChars(scriptName, varargin{:});

            validateattributes( obj, {'parallel.Cluster'}, {'scalar'}, 'batch', 'cluster', 1 );

            parallel.internal.cluster.checkNumberOfArguments('input', 1, inf, ...
                nargin, 'batch');

            pch = ProfileConfigHelper.buildApi2();
            % Parse the arguments in
            try
                batchHelper = BatchHelper2( pch, scriptName, varargin );
            catch err
                % Make all errors appear from batch
                throw(err);
            end

            % Deal with the Workspace and configuration.  Set the WorkspaceIn to the
            % caller if one wasn't supplied.  Note that this code has to exist here
            % because multiple evalin calls cannot be nested.  This code can't even be
            % put into a script, because evalin('caller') from the script just gets
            % this function's workspace and not the caller of this function.  If you
            % change this code, make sure you change the versions in @jobmanager/batch.m
            % and batch.m as well.
            if batchHelper.needsCallerWorkspace
                where = 'caller';
                % No workspace supplied - we need to make our own from the calling workspace
                vars = evalin(where, 'whos');
                % Loop over each variable in the calling workspace to get its value
                numVars = numel(vars);
                varNames = cell(numVars, 1);
                varValues = cell(numVars, 1);
                for ii = 1:numVars
                    varNames{ii} = vars(ii).name;
                    varValues{ii} = evalin(where, vars(ii).name);
                end
                batchHelper.filterAndSetCallerWorkspace(varNames, varValues);
            end

            % Check that a configuration is not set in the args
            if ~isempty(batchHelper.Configuration)
                error(message('parallel:cluster:BatchMethodProfileSpecified'));
            end
            batchHelper.Configuration = obj.Profile;

            % Actually run batch on the scheduler
            try
                job = batchHelper.doBatch(obj);
            catch err
                % Make all errors appear from batch
                throw(err);
            end
        end


    end


    methods (Static)
        function varargout = pfoaWrapper(f,nout,varargin)
            % Not meant to be called directly - only by parfevalOnAll.
            % This is a wrapper to run parfevalOnAll on one worker on the cluster
            % that starts a parpool with many ('Pool'). This is used to
            % circumvent the restrictions on communication between parpool
            % on the cluster and the external client.
            %
            % This code is called from kSlurm.rum, when itis called from
            % kSlur,.parfevalOnAll.
            %
            % Note that if nout >1 (i.e. the function to evaluate returns
            % outputs) the worker that starts the parfeval will block until
            % all parpool workers are done, then fetch the results so that
            % the client can fetch the results from the worker, using
            % fetchOutputs(job) where job is the output of amarel.parfevalOnAll(c)
            %
            % If nout ==0, this wrapper returns after starting the
            % parfevalOnAll job. (The future is lost)
            future= parfevalOnAll(f,nout,varargin{:});
            if nout >0
                % This will block on the cluster
                results= fetchOutputs(future);
                varargout = cell(1,nout);
                [varargout{1:nout}] = deal(results);
            end
        end

        % Prefs are all strings
        function v =  getpref(pref)
            % Retrieve a kSlurm preference
            arguments
                pref (1,:) {mustBeText} = ''
            end
            if isempty(pref)
                % Show all
                v = getpref(kSlurm.PREFGRP);
            else
                % Get a save preferred string value.
                if ispref(kSlurm.PREFGRP,pref)
                    v = string(getpref(kSlurm.PREFGRP,pref));
                else
                    v = "";
                end
            end
        end

        function setpref(pref,value)
            % Set one or more kSlurm preferences. Use this to define the
            % cluster host name, user, identity file and job storage.
            % For instance:
            % kSlurm.setpref('User','joe','IdentityFile','my_ssh_rsa',...
            %               'Host','supercomputer.university.edu',...
            %               'RemoteStorage','/scratch/joe/jobStorage')
            % Those settings will persist across Matlab sessions (but not
            % Matlab versions) and allow you to call kSlurm with fewer
            % input arguments.
            arguments (Repeating)
                pref
                value
            end
            if ~all(ismember(pref,kSlurm.PREFS))
                error('kSlurm only stores prefs for %s',strjoin(kSlurm.PREFS,'/'))
            end
            setpref(kSlurm.PREFGRP,pref,value);
        end

        function install()
            % Interactive install -  loop over the prefs to ask for values
            % then set.
            values= cell(1,numel(kSlurm.PREFS));
            i = 0;
            for p = kSlurm.PREFS
                i = i +1;
                values{i} = string(input("Preferred value for " + p + "?",'s'));
            end
            kSlurm.setpref(kSlurm.PREFS,values);
        end

    end
end