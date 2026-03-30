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
# We embed the manifest directly to avoid version drift and network issues
# at apply time. This is pinned to v0.28.2 (flannel) + v1.9.0 (cni-plugin).
echo "🌐 Installing Flannel pod network..."
multipass exec $MASTER_NAME -- kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# 5a. WAIT FOR POD OBJECT TO EXIST
# kubectl wait --selector fails immediately with exit code 1 if zero pods
# are found — it does NOT wait for pods to be created, only for conditions
# on pods that already exist. The DaemonSet controller needs a few seconds
# to schedule and create the pod object after the DaemonSet is applied.
echo "⏳ Waiting for Flannel pod object to be scheduled (up to 60s)..."
multipass exec $MASTER_NAME -- bash -c '
  for i in $(seq 1 12); do
    COUNT=$(kubectl get pods -n kube-flannel \
      --selector=app=flannel \
      --no-headers 2>/dev/null | wc -l)
    if [ "$COUNT" -gt "0" ]; then
      echo "✅ Flannel pod object found after attempt $i"
      exit 0
    fi
    echo "   attempt $i/12 — pod not yet scheduled, waiting 5s..."
    sleep 5
  done
  echo "❌ Flannel pod never appeared after 60s — check DaemonSet"
  kubectl describe daemonset kube-flannel-ds -n kube-flannel
  exit 1
'
# 5b. WAIT FOR FLANNEL POD TO BE READY
# Now that the pod exists, kubectl wait can safely poll its condition.
# We also check both init containers passed (install-cni-plugin, install-cni)
# as these copy the CNI binary and config to the host — without them the
# node stays NotReady with "cni plugin not initialized".
echo "⏳ Waiting for Flannel pod to be Ready (up to 3 minutes)..."
multipass exec $MASTER_NAME -- \
  kubectl wait --namespace kube-flannel \
    --for=condition=ready pod \
    --selector=app=flannel \
    --timeout=180s
# 5c. VERIFY CNI ARTIFACTS WERE WRITTEN TO THE HOST
# The two init containers should have written:
#   /opt/cni/bin/flannel        — the CNI binary  (install-cni-plugin)
#   /etc/cni/net.d/10-flannel.conflist — the CNI config (install-cni)
# If either is missing, kubelet will report "cni plugin not initialized"
# and the node will stay NotReady even though the Flannel pod shows Running.
echo "🔍 Verifying CNI binary and config were written to host..."
multipass exec $MASTER_NAME -- bash -c '
  ERRORS=0
  if [ -f /opt/cni/bin/flannel ]; then
    echo "✅ CNI binary present:  /opt/cni/bin/flannel"
  else
    echo "❌ CNI binary MISSING:  /opt/cni/bin/flannel"
    echo "   install-cni-plugin init container may have failed"
    ERRORS=$((ERRORS + 1))
  fi
  if [ -f /etc/cni/net.d/10-flannel.conflist ]; then
    echo "✅ CNI config present:  /etc/cni/net.d/10-flannel.conflist"
  else
    echo "❌ CNI config MISSING:  /etc/cni/net.d/10-flannel.conflist"
    echo "   install-cni init container may have failed"
    ERRORS=$((ERRORS + 1))
  fi
  if [ "$ERRORS" -gt "0" ]; then
    echo ""
    echo "📋 Init container logs for debugging:"
    kubectl logs -n kube-flannel \
      $(kubectl get pod -n kube-flannel --selector=app=flannel \
        --no-headers -o custom-columns=":metadata.name") \
      -c install-cni-plugin 2>/dev/null || true
    kubectl logs -n kube-flannel \
      $(kubectl get pod -n kube-flannel --selector=app=flannel \
        --no-headers -o custom-columns=":metadata.name") \
      -c install-cni 2>/dev/null || true
    exit 1
  fi
'
# 5d. WAIT FOR NODE TO BECOME READY
echo "⏳ Giving kubelet time to process CNI config..."
sleep 15
# Check kubelet is actually running before we wait
echo "🔍 Checking kubelet status..."
multipass exec $MASTER_NAME -- bash -c '
  if ! systemctl is-active --quiet kubelet; then
    echo "❌ kubelet is NOT running — dumping status:"
    systemctl status kubelet --no-pager -l
    journalctl -u kubelet --no-pager -n 30
    exit 1
  fi
  echo "✅ kubelet is running"
'
echo "⏳ Waiting for master node to become Ready (up to 6 minutes)..."
multipass exec $MASTER_NAME -- \
  kubectl wait --for=condition=Ready \
    node/$MASTER_NAME \
    --timeout=360s || {
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
# FIX: Ensure double-hyphens (--) are used, not em-dashes (—)
multipass exec $MASTER_NAME -- sudo kubeadm token create --print-join-command > $PROJECT_ROOT/out/join-command.sh
chmod +x $PROJECT_ROOT/out/join-command.sh
echo "=================================================="
echo "✅ Master Initialization Complete!"
echo "=================================================="
