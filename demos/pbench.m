function times= pbench(count)
%PBENCH  MATLAB Benchmark modified for the Parallel Computing
%Toolbox examples.
% 
%   PBENCH times four different MATLAB operations and
%   compares the execution speed.  The four operations are:
%   
%    LU       LAPACK.                  Floating point, regular memory access.
%    FFT      Fast Fourier Transform.  Floating point, irregular memory access.
%    ODE      Ordinary diff. eqn.      Data structures and functions.
%    Sparse   Solve sparse system.     Sparse linear algebra.
%
%   See also BENCH

%   Copyright 2007-2018 The MathWorks, Inc.
    
    if nargin < 1
        count = 1; 
    end
    
    times = zeros(count, 4);
    % Use a private stream to avoid resetting the global stream
    stream = RandStream('mt19937ar');
    
    bench_lu(stream);
    bench_fft(stream);
    bench_ode;
    bench_sparse;
    
    for k = 1: count
        % LU, n = 2400.
        times(k,1) = bench_lu(stream);
        % FFT, n = 2^21.
        times(k,2) = bench_fft(stream);
        % ODE. van der Pol equation, mu = 1
        times(k,3) = bench_ode;
        % Sparse linear equations
        times(k,4) = bench_sparse;
    end
end

function [t, n] = bench_lu(stream)
% LU, n = 2400.
n = 2400;
reset(stream,0);
A = randn(stream,n,n);
tic
B = lu(A); 
t = toc;
end

function [t, n] = bench_fft(stream)
% FFT, n = 2^23.
n = 2^23;
reset(stream,1);
x = randn(stream,1,n);
tic;
y = fft(x);
t = toc;
end

function dydt = vanderpol(~,y)
%VANDERPOL  Evaluate the van der Pol ODEs for mu = 1
dydt = [y(2); (1-y(1)^2)*y(2)-y(1)];
end

function [t, n] = bench_ode
% ODE. van der Pol equation, mu = 1
F = @vanderpol;
y0 = [2; 0]; 
tspan = [0 eps];
[s,y] = ode45(F,tspan,y0);  %#ok Used  to preallocate s and  y   
tspan = [0 450];
n = tspan(end);
tic
[s,y] = ode45(F,tspan,y0); %#ok Results not used -- strictly for timing
t = toc;
end

function [t, n] = bench_sparse
% Sparse linear equations
n = 300;
A = delsq(numgrid('L',n));
n = size(A, 1);
b = sum(A)';
tic
x = A\b; %#ok Result not used -- strictly for timing
t = toc;
end
