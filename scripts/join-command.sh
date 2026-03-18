#!/bin/bash
set -e
sudo kubeadm join 192.168.2.126:6443 --token t5nb84.5piukcmmcn1dscuo --discovery-token-ca-cert-hash sha256:c6808f8455900ac21514159837090a04330a3de219da726f67d9903a33b0f62e 
