# Matlab Parallel Computing on a SLURM Cluster

This repository was forked from a Mathworks' general purpose repository for SLURM schedulers. The original README is here [README.SLURM.md](./README.SLURM.md).

But, basically, I read that for you and created a convenience wrapper to make the connection to a Cluster (specifically, the AmarelRutgers HPC cluster) a bit easier.

What you should do:

1. Create an SSH key to access Amarel without typing a password following these instructions:

    [Passwordless access and file transfers using SSH keys](https://sites.google.com/view/cluster-user-guide#h.jgwrkm9e9rwg)

    Use an empty (i.e. no) passphrase and store the private key file somewhere safe on your client. (e.g., c:/keys/amarel_private).

1. Clone this repository to your workstation (you can pick any folder):

    ```git clone https://github.com/klabhub/matlab-parallel-amarel-plugin 'c:\github\matlab-parallel-amarel-plugin'```

1. Start Matlab and add the repo folder to your path:
```addpath('c:\gitub\matlab-parallel-amarel-plugin')```

1. Save the path for future sessions:

    ```savepath```

1. Set your preferences for connection to the cluster
    Adjust these to your needs:

    `
    kSlurm.setpref('user','bart',...
                    'identityFile','c:/keys/amarel_private',...
                    'host','amareln.hpc.rutgers.edu',...
        'remoteStorage','/scratch/bart/jobStorage',...
        'matlabRoot','/opt/sw/packages/MATLAB/R2022a')
    `
    
    Note that the version of Matlab on your workstation should match the one you use on the cluster (here R2022a).
1. In Matlab try to connect (For the Amarel cluster you need to be on the Rutgers network, use a VPN from home). You should see some information on the partitions and nodes on Amarel.

    ```c = kSlurm```

1. Work your way through these demos (in the demos folder) to see some typical use scenarios:

    ```batchDemo.m```, ```parfevalOnAllDemo.m```,```parforDemo. m```
