Instructions
============

First, a few requirements:

- Install multipass
- Install qemu / Hypervisor 
- Install Gitbash: https://git-scm.com/install/

Run each of the following using ". $FILENAME" command in a bash prompt:

```
. ./k8s
. ./k8s_dashboard_and_metrics
. ./demo (just to verify the cluster and have some health check components)
. ./longhorn
. ./oclaw (creates the actual gateway listening on 18789) 

see: runit for step-by-step

```

This will create a 3 node kubernetes cluster, set up the dashboard and metrics for it, and install a simple Voting App. consisting of a frontend, backend and a database for use in verifying the infrastructure. 

Then, it installs and configures longhorn for a very scaled down PVC to work with a single replica (1 pod) version of Open Claw 

That's all!!!


