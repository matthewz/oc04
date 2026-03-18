#!/bin/bash
set -e
sudo kubeadm join 192.168.2.116:6443 --token ziq7yv.2akh2mw7zbwn6m2j --discovery-token-ca-cert-hash sha256:dc15d2ae8b37a8feb1f17dccc2b7196b2451dbf9a1cf575f77108b5dab8d03c2 
