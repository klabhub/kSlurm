# Matlab Parallel Computing on a SLURM Cluster

Bart Krekelberg
June 2023

This repository was forked from a Mathworks' general purpose repository for SLURM schedulers. The original README is here [README.SLURM.md](./README.SLURM.md).

But, basically, I read that for you, created a convenience wrapper class to make the connection to a Cluster (specifically, the Rutgers Amarel HPC cluster) a bit easier, and added some 
missing pieces to the code (such as transmitting environment variables, startup folders, and reusing some settings for all jobs).

What you should do:

1. Create an SSH key to access Amarel without typing a password following these instructions:

    [Passwordless access and file transfers using SSH keys](https://sites.google.com/view/cluster-user-guide#h.jgwrkm9e9rwg)

    Use an empty (i.e. no) passphrase and store the private key file somewhere safe on your client. (e.g., c:/keys/amarel_private).

1. Clone this repository to your workstation (you can pick any folder):

    ```git clone https://github.com/klabhub/kSlurm 'c:\github\kSlurm'```
1. Start Matlab and open ```tutorial.mlx```

## Parallel Code Development

Although this package should make it a bit easier to run your analysis code on the Amarel cluster, there will still be hurdles and unexpected outcomes. One of the biggest issues is that much of the code execution happens in the dark (somewhere far away on an unknown computer) and without access to the command line output it is often difficult to find out what went wrong. To reduce your pain, I'd recommend the following steps.

1. Write code without parallelization first and run it on your local workstation. Test it, debug it, all using small datasets. Keep all code in a git  repository.
1. Once this  works flawlessly on your local workstation, clone the git repository to the cluster. Use an interactive session (```srun -n 1 -c 4 --mem=6GB --pty bash```) to start Matlab, and test that, given the same data, the code runs on the cluster.
1. Go back to your workstation, start adding parallel processing features. For instance, if you have a function that analyses one item (a file, a neuron) then write a script that calls that function for many items (files, neurons) in a for loop. Once it works, replace the for loop with a parfor loop, but use a local pool of 2 workers (```parpool(2)```) to test it. Your code will look something like this:

```matlab
    ops = parforOptions(parpool(2));
    parfor (i=1:nrItems,ops)
        out(i) = my_function(i) 
    end
```

1. Test this exact same code in an interactive session on the cluster.
1. Once all of this works, go back to the workstation, setup a kSlurm object called c, and use its options in the parfor loop (```ops= parforOpts(c))```) (Note parforOpts, not Options!).


## Change Log
June 2023 -  Initial version.
