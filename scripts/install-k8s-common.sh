#!/bin/bash
set -e
# Arguments
VM_NAME="${1}"
K8S_VERSION="${2:-1.28.0-1.1}"
POD_NETWORK_CIDR="${3:-10.244.0.0/16}"
echo "=================================================="
echo "Installing Kubernetes on ${VM_NAME}"
echo "=================================================="
echo "Kubernetes Version: ${K8S_VERSION}"
echo "Pod Network CIDR: ${POD_NETWORK_CIDR}"
echo "=================================================="
multipass exec ${VM_NAME} -- bash -c "
set -e
echo '🔧 Configuring system...'
# Disable swap
set -x
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
# Configure sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
set +x
echo '📦 Installing containerd...'
# Install containerd
set -x
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
# Install containerd
sudo apt-get install -y containerd
# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# Enable SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
echo '📦 Installing Kubernetes packages...'
# Add Kubernetes apt repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
# Install Kubernetes packages
sudo apt-get update
sudo apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
sudo apt-mark hold kubelet kubeadm kubectl
set +x
echo '✅ Kubernetes installation complete on ${VM_NAME}!'
"
echo "✅ Installation complete on ${VM_NAME}!"
echo "=================================================="
