#!/bin/bash
set -e
sudo kubeadm join 192.168.2.128:6443 --token 9jazh8.k5s9ggp2tb0pwurs --discovery-token-ca-cert-hash sha256:0a7d63609a253eebeb5d0a36bee55cc63df0c66983603e83f8f6f5da987f7b58 
