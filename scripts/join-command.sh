#!/bin/bash
set -e
sudo kubeadm join 192.168.2.94:6443 --token gxcnyc.bhhkt4ud6gedff5f --discovery-token-ca-cert-hash sha256:c52a319c1141fae20d15eaa4645d8db884be0b36f5bc93db13e4469ce518a0d6 
