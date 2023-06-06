# Matlab Parallel Computing on a SLURM Cluster

This repository was forked from a Mathworks' general purpose repository for SLURM schedulers. The original README is here [README.SLURM.md](./README.SLURM.md).

But, basically, I read that for you and created a convenience wrapper to make the connection to a Cluster (specifically, the AmarelRutgers HPC cluster) a bit easier.

What you should do:

1. Create an SSH key to access Amarel without typing a password following these instructions:

    [Passwordless access and file transfers using SSH keys](https://sites.google.com/view/cluster-user-guide#h.jgwrkm9e9rwg)

    Use an empty (i.e. no) passphrase and store the private key file somewhere safe on your client. (e.g., c:/keys/amarel_private).

1. Clone this repository to your workstation (you can pick any folder):

    ```git clone https://github.com/klabhub/kSlurm 'c:\github\kSlurm'```
1. Start Matlab and open tutorial1.mlx


Bart Krekelberg
June 2023