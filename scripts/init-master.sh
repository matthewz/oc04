#!/bin/bash
set -e
# Arguments
MASTER_NAME=$1
MASTER_IP=$2
POD_CIDR=$3
SVC_CIDR=$4
PROJECT_ROOT=$5
echo "=================================================="
echo "      Initializing Kubernetes Master Node         "
echo "=================================================="
echo "Master Name:      $MASTER_NAME"
echo "Master IP:        $MASTER_IP"
echo "Pod Network CIDR: $POD_CIDR"
echo "Service CIDR:     $SVC_CIDR"
echo "=================================================="
# 1. PRE-FLIGHT CLEANUP (The SRE Way)
# If a previous attempt failed, kubeadm will refuse to run.
# We force a reset to clear out the "ghosts" of previous failures.
echo "🧹 Cleaning up any previous Kubernetes state..."
multipass exec $MASTER_NAME -- sudo kubeadm reset -f || true
multipass exec $MASTER_NAME -- sudo rm -rf /etc/cni/net.d || true
# FIX: Use explicit path instead of $HOME which expands on the LOCAL machine
# and would delete your Mac's ~/.kube directory!
multipass exec $MASTER_NAME -- bash -c 'sudo rm -rf /home/ubuntu/.kube' || true
# 2. DISABLE SWAP (The #1 reason kubeadm fails)
echo "🚫 Ensuring Swap is disabled..."
multipass exec $MASTER_NAME -- sudo swapoff -a
# 3. INITIALIZE CLUSTER
# We use --ignore-preflight-errors to handle small resource inconsistencies
# that happen in virtualized environments.
echo "🚀 Running kubeadm init (this may take 1-2 minutes)..."
multipass exec $MASTER_NAME -- sudo kubeadm init \
  --pod-network-cidr=$POD_CIDR \
  --service-cidr=$SVC_CIDR \
  --apiserver-advertise-address=$MASTER_IP \
  --ignore-preflight-errors=NumCPU,Mem
# Check if kubeadm init actually worked
if [ $? -ne 0 ]; then
  echo "❌ Error: kubeadm init failed!"
  exit 1
fi
# 4. CONFIGURE KUBECTL FOR THE UBUNTU USER INSIDE THE VM
# FIX: Use single-quoted heredoc to prevent local variable expansion.
# Without quotes on EOF, $HOME and $(id -u) would be evaluated on your Mac.
echo "⚙️  Configuring kubeconfig inside the VM..."
multipass exec $MASTER_NAME -- bash -c '
  mkdir -p /home/ubuntu/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  sudo chown $(id -u ubuntu):$(id -g ubuntu) /home/ubuntu/.kube/config
'
# 5. INSTALL POD NETWORK (Flannel)
# Without this, nodes will stay in "NotReady" status forever.
echo "🌐 Installing Flannel pod network..."
multipass exec $MASTER_NAME -- \
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# 6. CAPTURE JOIN COMMAND
# We save this to a local file so the worker nodes can read it to join.
# Note: join-worker.sh generates a fresh token dynamically, but we save
# this here as a reference/fallback.
echo "🔑 Generating join command for workers..."
mkdir -p $PROJECT_ROOT/out
multipass exec $MASTER_NAME -- sudo kubeadm token create --print-join-command > $PROJECT_ROOT/out/join-command.sh
chmod +x $PROJECT_ROOT/out/join-command.sh
echo "✅ Master Initialization Complete!"
echo "=================================================="
