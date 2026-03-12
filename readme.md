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
. ./demo

```

This will create a 3 node kubernetes cluster, set up the dashboard and metrics for it, and install a simple Voting App. consisting of a frontend, backend and a database for use in verifying the infrastructure. 
