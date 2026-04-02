#!/bin/bash
set -e
# Arguments
NODE_NAME=$1
K8S_VERSION=$2  # Example: 1.28.0-1.1
echo "=================================================="
echo "  Installing K8s Common Binaries on $NODE_NAME   "
echo "=================================================="

#set -x
# 0. If kubelet is already there, don't waste CPU/Disk reinstalling
#echo "Checking for kubelet..."
#K8S_PATH=$(multipass exec "$NODE_NAME" -- which kubelet < /dev/null 2>&1) || true
#if [[ "$K8S_PATH" == *"kubelet"* ]]; then
#   echo "✅ K8s already installed on $NODE_NAME, skipping..."
#   exit 0
#fi
#set +x

# Extract the minor version (e.g., "1.28") from the full version string
# (e.g., "1.28.0-1.1") so we can build the correct repo URL dynamically.
# FIX: Previously the repo URL was hardcoded to v1.28 regardless of the
# K8S_VERSION variable passed in, meaning changing the variable had no effect.
K8S_MINOR=$(echo "$K8S_VERSION" | cut -d'.' -f1-2)
echo "Using Kubernetes minor version: $K8S_MINOR"
echo "🛠️  Configuring $NODE_NAME..."
# 1. Wait for apt locks to release (Common on fresh Multipass boots)
# Cloud-init runs apt in the background after first boot, so we must
# wait for it to finish before we try to install anything.
multipass exec "$NODE_NAME" -- bash -c '
  echo "Waiting for apt locks to release..."
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "  ...apt is busy, waiting 2s..."
    sleep 2
  done
  echo "✅ apt lock is free."
'
# 2. Prerequisites & Containerd
# FIX: Use single-quoted heredoc (<<'"'"'EOF'"'"') to prevent local shell
# from expanding variables like $HOME or $(...) before sending to the VM.
# Everything inside is evaluated remotely inside the VM.
multipass exec "$NODE_NAME" -- bash -c '
  set -e
  echo "📦 Installing prerequisites..."
  sudo apt-get update -y
  sudo apt-get install -y apt-transport-https ca-certificates curl gpg
  # Load required kernel modules for Kubernetes networking
  # FIX: Original script had "k8s.conf" written as a module name inside
  # the file, which is not a real kernel module and causes modprobe errors.
  # The file should only contain the actual module names: overlay, br_netfilter
  echo "🔧 Configuring kernel modules..."
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter
  # Enable required sysctl settings for K8s networking
  echo "🔧 Configuring sysctl settings..."
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system
  # Install and configure Containerd as the container runtime
  echo "📦 Installing containerd..."
  sudo apt-get install -y containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  # Enable SystemdCgroup — required for kubeadm clusters.
  # Without this kubelet and containerd use different cgroup drivers
  # and the node will never reach Ready state.
  sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml
  sudo systemctl restart containerd
  echo "✅ Containerd configured and restarted."
'
# 3. Install K8s Binaries
# We pass K8S_MINOR into the VM as an environment variable using
# the -v flag pattern so the remote bash script can use it safely
# without any heredoc quoting gymnastics.

echo "📦 Installing Kubernetes binaries (version ~${K8S_VERSION})..."
multipass exec "$NODE_NAME" -- bash -c "
  set -e
  # Add the Kubernetes apt repo for the correct minor version
  # FIX: Previously hardcoded to v1.28. Now uses the version passed
  # in from Terraform via the K8S_VERSION variable.

  sudo mkdir -p -m 755 /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key | \
      sudo gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  else
    echo '✅ Kubernetes GPG key already exists, skipping...'
  fi
  if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]; then
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /' | \
      sudo tee /etc/apt/sources.list.d/kubernetes.list
  else
    echo '✅ Kubernetes apt source already exists, skipping...'
  fi

  sudo apt-get update -y


  # FIX: Previously installed latest available version, ignoring K8S_VERSION.
  # Now pins to the exact version passed in so all nodes are consistent.
  sudo apt-get install -y \
    kubelet=${K8S_VERSION} \
    kubeadm=${K8S_VERSION} \
    kubectl=${K8S_VERSION}
  # Hold the packages to prevent unintended upgrades via apt upgrade
  sudo apt-mark hold kubelet kubeadm kubectl
"

echo "✅ Common K8s setup complete for $NODE_NAME"
echo "=================================================="

