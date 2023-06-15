function [info]  = stateCheck
info.path = string(strsplit(path,':'));
info.pwd = pwd;
info.host=getenv('hostname');
info.nodeList = getenv('SLURM_JOB_NODELIST');
info.jobID = getenv('SLURM_JOB_ID');
info.env = getenv('TESTENV');  % See tutorial1.mlx
info.tbx = matlab.addons.installedAddons;
end