#!/bin/bash
set -e
sudo kubeadm join 192.168.2.141:6443 --token qctaq2.o1nzjemfngqacwq4 --discovery-token-ca-cert-hash sha256:be71a7c2256ed4a261c207e4328a86e43a573c0ff377e62f555f8cafefca4998 
