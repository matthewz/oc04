Instructions
============

- First, a few requirements: install multipass, qemu / Hypervisor, Python, Helm, Helmfile, and GitBash (https://git-scm.com/install/)

- Run the following:

```
run_pipeline.py apps
```

Other Information
=================

- The 'pipeline.yaml' file will specify a 3 node kubernetes cluster, set up the dashboard and metrics for it, and install Open Claw in a single replica instance with very strict 'NetworkPolicy' resource.  
- It also installs and configures longhorn for using very scaled down PVC(s) and schedule regular snapshots to a NAS for backups/archival.
- Also included in the pipeline is a VM dedicate to running Hashicorp Vault for secrets management. 
- See 'howto' file for random/hodgepodge of possibly useful commands.

Some things yet to do
=====================
- Pod Hardening and "walled garden" strategy
- Set up Grafana dashboard for observability
- Configure communication channel such as: slack
- Explore OpenClaw skills and plugins and set up more agent(s)
- Implement backup and restore strategies for "salient data" as part of 'infrastructure' step in pipeline.yaml:
  - in order to make VM's ephemeral and scale oclaw01 as oclaw02, oclaw03, etc...
- (Re-)Evaluate GitOps for configuration management via [Declarative] Jenkins or some other tool
- Try to get this working on Windows Hyervisor with just gitbash installed and other generic tools

.
.
.

That's all!!!


