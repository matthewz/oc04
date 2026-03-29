#!/bin/bash
set -e
NODE_NAME=$1
K8S_VERSION=$2 # Example: 1.28.0-1.1
POD_CIDR=$3
# 0. If kubelet is already there, don't waste CPU/Disk reinstalling
if multipass exec $1 -- which kubelet > /dev/null 2>&1; then
   echo "K8s already installed on $1, skipping..."
   exit 0
fi
echo "🛠️  Configuring $NODE_NAME..."
# 1. Wait for apt locks to release (Common on fresh Multipass boots)
multipass exec "$NODE_NAME" -- bash -c "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo 'Waiting for other apt processes...'; sleep 2; done"
# 2. Skip if already installed
if multipass exec "$NODE_NAME" -- command -v kubeadm >/dev/null 2>&1; then
    echo "✅ Kubernetes binaries already present on $NODE_NAME. Skipping install."
    exit 0
fi
# 3. Prerequisites & Containerd
multipass exec "$NODE_NAME" -- bash -c "
  sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
  
  # Forwarding IPv4 and letting iptables see bridged traffic
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system
  # Install Containerd
  sudo apt-get install -y containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  sudo systemctl restart containerd
"
# 4. Install K8s Binaries
multipass exec "$NODE_NAME" -- bash -c "
  # Add K8s Repo (Updated for newer versions)
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo apt-get update
  sudo apt-get install -y kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl
"
echo "✅ Common setup complete for $NODE_NAME"
