#!/bin/bash
set -e
sudo kubeadm join 192.168.2.97:6443 --token a37tps.ve08508q9krwtf6h --discovery-token-ca-cert-hash sha256:492036bf8c9fc2b7a7e96b5f7028a642733ae6a5ffd09411d5298d61e38e60c9 
