% A silly dumb-parellel loop.
% Each i will run on its own worker. 
% See also batchExample
parfor i = 1:1024
  A(i) = sin(i*2*pi/1024);
end