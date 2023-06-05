classdef kSlurm < parallel.cluster.Generic
    % Wrapper code around a cluster object for the SLURM scheduler to
    % simplify connecting and submitting jobs from a Windows client to a
    % SLURM cluster.
    %
    % 
    % BK - June 2023

    properties (Constant)
        PREFGRP = "kSlurm"  % Group that stores string preferences for kSlurm
        PREFS   = ["user","identityFile","host","remoteStorage","matlabRoot"];
    end

    properties (SetAccess = public)
        batchDefaults =struct('CaptureDiary',true,'CurrentFolder','.'); % Batch only
        jobDefaults = struct('AutoAttachFiles',false,'AutoAddClientPath',false);

        gitFolders  (1,:) cell = {}
    end

    properties (SetAccess =protected)
    end


    properties (Dependent)

    end

  
    methods

    end

    methods (Access=public)

   
        function [status,stdout] = runCommand(c,cmd)
            % Run any unix command (cmd) on the cluster head node.
            % OUTPUT
            % stdout = What was written to the command line
            % status = The exit code of the command
            rc = getRemoteConnection(c);
            [a,b] = runCommand(rc,cmd);
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
            % All parameter value pairs that can be specified in the call
            % to parforOptions can be specified here too.
            %
            % See also parforOptions

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
            job = batch(c,file,defs{:},varargin{:});
        end

        function job =fun(c,f,nout,args,varargin)
            % Analogous to script, now for functions.
            %
            % To retrieve the output of the parallel workers, use
            % fetchOutputs(job)
            %
            %   See also parallel.Cluster.batch
            arguments
                c (1,1) kSlurm
                f (1,1) {mustBeA(f,'function_handle')}    % Function to run on the cluster
                nout (1,1) double {mustBePositive,mustBeInteger}  % Number of output arguments for the function f
                args (1,:) cell = {}                    % Cell array with input arguments for the function f
            end
            arguments (Repeating)
                varargin    % Parameter value pairs for parralel.batch
            end
            % By passing the defaults first, and the varargin later,
            % the user can overrule the defaults for a specific job
            defs = cat(2,namedargs2cell(c.batchDefaults),namedargs2cell(c.jobDefaults));
            job = batch(c,f,nout,args,defs{:},varargin{:});
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
                nout (1,1) double {mustBePositive,mustBeInteger} % Number of output args for f
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
            % hours      - The requested wall time hours    [1]
            % muinutes   - The requested wall time minutes  [0]
            % nrThreads  - Number threads per worker      [1]
            % nrWorkers - The maximum number of workers that can be requested [10]
            % host      - The host name or ip address of the cluster [getpref('host')]
            % remoteStorage - The location where job files will be stored [getpref('remoteStorage']
            % matlabRoot  - The Root of the Matlab installation on the cluster. [getpref('matlabRoot')]
            % sbatchOptions - A string with additional options to pass to sbatch [""]
            %
            % OUTPUT
            % c -  The kSlurm Cluster object
            %
            % EXAMPLE
            % This can be called every session, with appropriate resource requests and
            % then used to create a parpool
            %  c = kSlurm('bart','path/to/file/bart_amareln_rsa','hours',1)
            %
            % Or, you can save the output as a named cluster profile, which can then be selected from the Parallel
            % button in the Command Window in future sessions
            %  saveAsProfile(c,'1 hour')
            %
            % NOTES
            % - because Matlab uses multithreading for some of its basic computations
            % having more than 1 thread per worker could speed up things, but each thread
            % is a core, so the resources oneis requesting goes up as
            % (nrWorkers*nrThreads). For any given application testing whether the
            % additional threads are "worth it" is advised.
            %
            arguments
                user  = kSlurm.getpref('user')
                identityFile = kSlurm.getpref('identityFile')
                pk.hours (1,1) double {mustBeInteger, mustBeInRange(pk.hours,0,24)} = 1
                pk.minutes (1,1) double {mustBeInteger,mustBeInRange(pk.minutes,0,60)} = 0
                pk.nrThreads (1,1) double {mustBeInteger,mustBeInRange(pk.nrThreads,1,64)} = 1
                pk.nrWorkers (1,1) double {mustBeInteger,mustBePositive} = 10
                pk.host (1,1) string = kSlurm.getpref('host');
                pk.remoteStorage (1,1) string = kSlurm.getpref('remoteStorage')
                pk.matlabRoot (1,1) string = kSlurm.getpref('matlabRoot')
                pk.sbatchOptions (1,1) string =""
            end
            if pk.matlabRoot==""
                clientVersion = ver('matlab').Release;
                clientVersion = clientVersion(2:end-1);
                pk.matlabRoot = sprintf('/opt/sw/packages/MATLAB/%s',clientVersion);
            end
            jobName= [getenv('COMPUTERNAME') '-MCP']; % Named the job after the submitting machine
            localStorage = tempdir;

            %% Setup the cluster object
            c =c@parallel.cluster.Generic;
            c.JobStorageLocation = struct('windows',localStorage,'unix',pk.remoteStorage);
            c.NumThreads = pk.nrThreads;
            c.NumWorkers = pk.nrWorkers;
            c.ClusterMatlabRoot = pk.matlabRoot; % Has to match the client's matlab version
            c.OperatingSystem = 'unix';
            c.HasSharedFilesystem = false;
            c.PluginScriptsLocation = fileparts(mfilename('fullpath'));
            c.AdditionalProperties.ClusterHost = pk.host;
            c.AdditionalProperties.RemoteJobStorageLocation =pk.remoteStorage;
            c.AdditionalProperties.Username = user;
            c.AdditionalProperties.IdentityFile = identityFile;
            c.AdditionalProperties.IdentityFileHasPassphrase = false;
            % All sbatch options can be added here
            c.AdditionalProperties.AdditionalSubmitArgs = pk.sbatchOptions + sprintf("-t %02d:%02d:00 --job-name %s",pk.hours, pk.minutes,jobName);

            % Try to connect and get some info on the cluster
            fprintf('Trying to connect to  %s ...\n',  c.AdditionalProperties.ClusterHost)
            fprintf('********************************\n')
            fprintf('Partition and Node information: \n')
            runCommand(c,'sinfo --format "%12P %.5a %.10l %.16F %m %20N"');
            fprintf('********************************\n')            
        end
        function delete(c)
           
            try
                 rc = getRemoteConnection(c);
                rc.disconnect
            catch me
                %Remote host may no longer be avaialbe
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
                % This will block on the cluste
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
            % Set one or more kSlurm preferences
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