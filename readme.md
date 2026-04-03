Instructions
============

First, a few requirements:

- Install multipass
- Install qemu / Hypervisor 
- Install Python
- Install Helm
- Install Helmfile
- Install Gitbash: https://git-scm.com/install/

Run the following:
```
python run_pipeline.py
```
See howto file for useful commands.

This will create a 3 node kubernetes cluster, set up the dashboard and metrics for it, and install a simple Voting App. consisting of a frontend, backend and a database for use in verifying the infrastructure. 

Then, it installs and configures longhorn for a very scaled down PVC to work with a single replica (1 pod) version of Open Claw. 

That's all!!!


