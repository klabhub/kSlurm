function variables  = addEnvironmentVariables(variables,cluster,job)
% Combine Matlab environment with Cluster level and Job level enivironment
% variables. Called from submitFcn and then passed to the workers.
%
 


% Get the EnvironmentVariables specified as part of the Cluster object 
% (c.UserData = {'MYENV','bla';'AnotherEnv','Bla'}'
if isfield(cluster.UserData, 'EnvironmentVariables') && ~isempty(cluster.UserData.EnvironmentVariables)
    ev= cluster.UserData.EnvironmentVariables;
    if isstruct(ev)
        ev = namedargs2cell(ev);
    end
    ev = reshape(ev,[],numel(ev)/2)';
    variables = cat(1,variables,ev);
end

% Retrieve the job-specific environemnt variables, and add those
% Note that these are evaulated on the client at the time of job submission
% (here). 
if ~isempty(job.EnvironmentVariables)
    jobEnv = cellfun(@getenv,job.EnvironmentVariables,'uni',false); 
    jobEnv  =cat(2,job.EnvironmentVariables',jobEnv');
    variables = cat(1,variables,jobEnv);
end

end