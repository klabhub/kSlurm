function [info]  = stateCheck
info.path = string(strsplit(path,':'));
info.pwd = pwd;
info.host=getenv('hostname');
info.nodeList = getenv('SLURM_JOB_NODELIST');
info.jobID = getenv('SLURM_JOB_ID');
info.dj_host = getenv('DJ_HOST');
