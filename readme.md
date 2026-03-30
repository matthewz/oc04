Instructions
============

First, a few requirements:

- Install multipass
- Install qemu / Hypervisor 
- Install Gitbash: https://git-scm.com/install/

Run each of the following using ".(dot) $FILENAME", or, running the script as shown in bash prompt:

```
sudo -v # pre-authorize for subsequent commands in the .sh scripts
(time ./k8s-rebuild.sh)                1> k8s-rebuild_out.txt                2>&1 &
(time ./setup-k8s-dashboard.sh)        1> setup-k8s-dashboard_out.txt        2>&1 &
. ./demo 
(time ./longhorn-rebuild.sh)           1> longhorn-rebuild_out.txt           2>&1 &
. ./oclaw

```

See howto file for useful commands.

This will create a 3 node kubernetes cluster, set up the dashboard and metrics for it, and install a simple Voting App. consisting of a frontend, backend and a database for use in verifying the infrastructure. 

Then, it installs and configures longhorn for a very scaled down PVC to work with a single replica (1 pod) version of Open Claw 

That's all!!!


