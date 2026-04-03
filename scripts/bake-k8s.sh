#!/bin/bash
# SAVE THIS AS: scripts/bake-k8s.sh
set -e
K8S_VERSION=$1  # e.g., 1.28.0-1.1
K8S_MINOR=$(echo "$K8S_VERSION" | cut -d'.' -f1-2)
echo "=================================================="
echo "  Baking K8s Binaries (Version: $K8S_VERSION)     "
echo "=================================================="
# 1. Wait for apt locks (Standard procedure)
echo "Waiting for apt locks to release..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "  ...apt is busy, waiting 2s..."
  sleep 2
done
# 2. Prerequisites & Containerd
echo "📦 Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
echo "🔧 Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
echo "🔧 Configuring sysctl settings..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
echo "📦 Installing containerd..."
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml
sudo systemctl restart containerd
# 3. Install K8s Binaries
echo "📦 Adding Kubernetes Repos (v${K8S_MINOR})..."
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key | \
  sudo gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -y
echo "📦 Installing kubelet, kubeadm, kubectl..."
sudo apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
sudo apt-mark hold kubelet kubeadm kubectl
echo "🐳 Pre-pulling Kubernetes control plane images..."
sudo kubeadm config images pull --kubernetes-version "${K8S_VERSION%-*}" # Trims the -1.1 part
# Add this to the end of bake-k8s.sh (optional but recommended)
sudo rm -f /etc/hostname
sudo truncate -s 0 /etc/machine-id
sudo rm -rf /var/lib/cloud/instances/*
echo "✅ K8s Bake Complete!"
