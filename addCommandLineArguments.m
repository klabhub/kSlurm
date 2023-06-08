function args = addCommandLineArguments(cluster,args)
% Add command line arguments specified as UserData
%
% Currently only cluster.UserData.StartupFolder is used.


if isfield(cluster.UserData,'StartupFolder') && ~(cluster.UserData.StartupFolder=="") 
    args = [args  ' -sd ' char(cluster.UserData.StartupFolder)]; 
end

