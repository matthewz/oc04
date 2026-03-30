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
echo "🌐 Installing Flannel pod network..."
multipass exec $MASTER_NAME -- kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# 5a. WAIT FOR POD OBJECT TO EXIST
echo "⏳ Waiting for Flannel pod object to be scheduled (up to 2 minutes)..."
multipass exec $MASTER_NAME -- bash -c '
  for i in $(seq 1 24); do
    COUNT=$(kubectl get pods -n kube-flannel \
      --selector=app=flannel \
      --no-headers 2>/dev/null | wc -l)
    if [ "$COUNT" -gt "0" ]; then
      echo "✅ Flannel pod object found after attempt $i"
      exit 0
    fi
    echo "   attempt $i/24 — pod not yet scheduled, waiting 5s..."
    sleep 5
  done
  echo "❌ Flannel pod never appeared after 2 minutes — checking DaemonSet"
  kubectl describe daemonset kube-flannel-ds -n kube-flannel
  exit 1
'
# 5b. WAIT FOR FLANNEL POD TO BE READY
echo "⏳ Waiting for Flannel pod to be Ready (up to 5 minutes)..."
multipass exec $MASTER_NAME -- \
  kubectl wait --namespace kube-flannel \
    --for=condition=ready pod \
    --selector=app=flannel \
    --timeout=300s
# 5c. VERIFY CNI ARTIFACTS AND NUDGE KUBELET
echo "🔍 Verifying CNI binary and config were written to host..."
multipass exec $MASTER_NAME -- bash -c '
  if [ -f /etc/cni/net.d/10-flannel.conflist ] && [ -f /opt/cni/bin/flannel ]; then
    echo "✅ CNI artifacts detected."
    echo "🔄 Restarting kubelet to force CNI recognition..."
    sudo systemctl restart kubelet
  else
    echo "❌ CNI artifacts missing - checking init container logs..."
    kubectl logs -n kube-flannel -l app=flannel -c install-cni-plugin --tail=20
    kubectl logs -n kube-flannel -l app=flannel -c install-cni --tail=20
    exit 1
  fi
'
# 5d. WAIT FOR NODE TO BECOME READY
# We give this a generous 10-minute timeout for slow local environments
echo "⏳ Waiting for master node to become Ready (up to 10 minutes)..."
multipass exec $MASTER_NAME -- \
  kubectl wait --for=condition=Ready \
    node/$MASTER_NAME \
    --timeout=600s || {
      echo "❌ Node never became Ready — dumping diagnostics:"
      multipass exec $MASTER_NAME -- kubectl describe node/$MASTER_NAME
      multipass exec $MASTER_NAME -- journalctl -u kubelet --no-pager -n 50
      exit 1
    } 
# 5e. PRINT FINAL STATE
echo "📋 Final cluster state:"
multipass exec $MASTER_NAME -- kubectl get nodes -o wide
echo ""
multipass exec $MASTER_NAME -- kubectl get pods -A
# 6. CAPTURE JOIN COMMAND
echo "🔑 Generating join command for workers..."
mkdir -p $PROJECT_ROOT/out
multipass exec $MASTER_NAME -- sudo kubeadm token create --print-join-command > $PROJECT_ROOT/out/join-command.sh
chmod +x $PROJECT_ROOT/out/join-command.sh
echo "=================================================="
echo "✅ Master Initialization Complete!"
echo "=================================================="
