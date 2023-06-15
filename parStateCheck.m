function [info]  = parStateCheck(nrWorkers)

parfor i=1:nrWorkers
    info(i) = stateCheck;
end