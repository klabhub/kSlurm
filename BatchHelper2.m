% Helper Class for activities related to batch in API2

%  Copyright 2010-2018 The MathWorks, Inc.

classdef (Hidden, Sealed) BatchHelper2 < parallel.internal.cluster.AbstractBatchHelper

    properties ( Constant, GetAccess = protected )
        % We never allow vectorized batch
        AllowVectorizedBatch = false;
    end

    methods
        function obj = BatchHelper2( varargin )
            obj@parallel.internal.cluster.AbstractBatchHelper( varargin{:} );
        end
        function job = doBatch(obj, sched)
            validateattributes( sched, {'parallel.Cluster'}, {'scalar'} );
            if obj.PoolSize(end) > 0
                jobConstructor = @(cluster, args) ...
                    cluster.createCommunicatingJob( args{:}, 'Type', 'Pool', ...
                    'ExecutionMode', parallel.internal.types.ExecutionMode.Batch );
            else
                jobConstructor = @(cluster, args) ...
                    cluster.createJob( args{:} );
            end
            jobPVPairs = obj.getCreateJobInputs;
            job        = jobConstructor(sched, jobPVPairs);
            jobCleanup = onCleanup(@() iDeleteIfPending(job));

            job.hSetProperty( {'ApiTag', 'Tag'}, {obj.ApiTag, obj.Tag} );

            % If anything fails from here we need to destroy the job as it won't be
            % passed back to the user
            try
                % No need for Profile, applies automatically.
                [functionToRun, numArgsOut, allArgsIn, taskPVPairs, taskDeps] = ...
                    obj.getCreateTaskInputs( 'CaptureDiary', '' );
                % Create a task that will call executeScript
                tasks = job.createTask(functionToRun, numArgsOut, allArgsIn, taskPVPairs{:});


                % This is the only difference with the internal
                % BatchHelper2:that always does a dependency analysis,
                % regaradless of the AutoAttachFiles setting. 
                % As a consequence it will  try to add files that may only
                % exist on the cluster. BK - June 2023.
                if job.AutoAttachFiles
                    % Cache all the task dependencies on the job.
                    job.hSetDependentFiles(unique([taskDeps{:}], 'stable'));
                    % Add the dependencies to the tasks
                    for ii = 1:numel(tasks)
                        tasks(ii).hSetDependentFiles(taskDeps{ii});
                    end
                end
                % Submit the job
                job.submit;
            catch exception
                % Any error - we need to destroy the job
                if ~iPreserveJobs()
                    job.delete();
                end
                rethrow(exception)
            end
        end
    end

    methods (Access = private)
        function pvPairs = getCreateJobInputs(obj)
            % getCreateJobInputs - Determines the correct job constructor and creates the
            % PV-pairs that should be used with that constructor

            pvPairs = {'AutoAddClientPath', obj.AutoAddClientPath};

            % NB: no need for Profile, applies automatically

            % Only add the other job-related properties if the user specified them, or they are not
            % empty (i.e. we set them).  This helps us distinguish between the case where values
            % are empty because the user did not specify them, or if the user explicitly set them
            % to empty.
            if obj.UserSpecifiedJobName || ~isempty(obj.JobName)
                pvPairs = [pvPairs, 'Name', obj.JobName];
            end
            if obj.UserSpecifiedAutoAttachFiles
                pvPairs = [pvPairs, 'AutoAttachFiles', obj.AutoAttachFiles];
            end
            if obj.UserSpecifiedFileDependencies || ~isempty(obj.FileDependencies)
                pvPairs = [pvPairs, 'AttachedFiles', {obj.FileDependencies}];
            end
            if obj.UserSpecifiedPathDependencies || ~isempty(obj.PathDependencies)
                pvPairs = [pvPairs, 'AdditionalPaths', {obj.PathDependencies}];
            end
            if obj.UserSpecifiedEnvironmentVariables || ~isempty(obj.EnvironmentVariables)
                pvPairs = [pvPairs, 'EnvironmentVariables', {obj.EnvironmentVariables}];
            end
            if obj.PoolSize(end) > 0
                pvPairs = [pvPairs, 'NumWorkersRange', obj.PoolSize + 1];
            end
        end
    end
end

function iDeleteIfPending(job)
if isvalid(job) && strcmp(job.State, 'pending') && ~iPreserveJobs()
    job.delete();
end
end

function tf = iPreserveJobs()
[~, undoc] = pctconfig();
tf = undoc.preservejobs;
end