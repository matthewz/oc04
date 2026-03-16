#!/bin/bash
set -e
sudo kubeadm join 192.168.2.103:6443 --token ds7yhd.fknu0eqqr0mt8zm0 --discovery-token-ca-cert-hash sha256:0e603d79adfb5e398d17abaefef5670f7d62627adbaae0d054e9b089cbf8f1d6 
