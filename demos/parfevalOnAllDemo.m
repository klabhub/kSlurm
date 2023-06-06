%% Example 2 - Evaluating one function many times, without parfor
% This time you have a function that does not use a parfor, but 
% you want to evaluate it many times (for instance in a bootstrap
% procedure) and concatenate all of the results. 
%
% As an example we run a version of Matlab's bench function 
% that times how long certain numerical operations take and returns 1 vector
% output with timings.
%
% We want to run this on 20 workers.  (Note that this assumes preferences
% have already been set to define the preferred cluster; see README.md)
c=kSlurm('NumWorkers',21,'Hours',0,'Minutes',20);
% The workers will call the pbench function with the input argument 10 (to run the benchmark 10 times)
% and return 1 output.
job = parfevalOnAll(c,@pbench,1,{10},'Pool',20,'AttachedFiles',{'pbench'});

% Benchmark the client for comparison:
tClient = pbench(10);  % Ten repeats (here on the local machine)
tClient = mean(tClient); % Take the mean over the 10 repeats.

wait(job);
results = fetchOutputs(job); % Get the results from the cluster
tWorkers = results{1};  % 20 nodes time 10 repeats = 200 rows
tWorkers = mean(tWorkers); % Average over all repeats

% Compare the performance
figure(1);
clf;
ax1= subplot(1,2,1);
bar([tClient;tWorkers]');
xticklabels({'LU','FFT','ODE','Sparse'});
xlabel("Benchmark type");
ylabel("Benchmark execution time (seconds)");
workerNames = strcat("Worker ",string(1:size(tWorkers,1)));
legend({'Client',workerNames});
title 'Workers without multithreading' 
% For interpretation/explanation, see
% https://www.mathworks.com/help/parallel-computing/benchmark-your-cluster-workers.html

%% Example 2a.
% Part of the reason that the cluster does not do so well in the benchmarks is that the workers are single threaded.
% Lets try this with multithreading on the cluster - asking for workers that
% have 10 threads each
c=kSlurm('NumWorkers',3,'Hours',0,'Minutes',20,'NumThreads',10);
job = parfevalOnAll(c,@pbench,1,{5},'Pool',1,'AttachedFiles',{'pbench'});
wait(job);

results = fetchOutputs(job);
tWorkers = results{1};

% NOTE:  Although 'nrWorkers' was 3 above this only has one set of 5 repeats = 5 rows
% The reason is that the cluster object c only specifies the *maximum*
% nrWorkers, the jobs (fun/run) determine how many will actually be
% run.
%
% In this case we asked only 1 (Pool) to be available to the
% function. That single worker ran multithreaded (10 threads available;
% Matlab determines how many it actually uses). and then returned its 5 repeats.
%
% (To check this logic, try setting Pool to 2
% then there should be two workers available to do the work
% and parfevalOnAll will use both of them, so you should get 10 rows.)
tWorkers = mean(tWorkers);

% Compare the performance

ax2= subplot(1,2,2);
bar([tClient;tWorkers]');
xticklabels({'LU','FFT','ODE','Sparse'});
xlabel("Benchmark type");
ylabel("Benchmark execution time (seconds)");
workerNames = strcat("Worker ",string(1:size(tWorkers,1)));

title 'Workers with multithreading' 
linkaxes([ax1 ax2])