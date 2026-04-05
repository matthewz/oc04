#!/bin/bash
set -e
# Arguments
MASTER_NAME=$1
MASTER_IP=$2
POD_CIDR=$3
SVC_CIDR=$4
PROJECT_ROOT=$5
echo "DEBUG: Project Root is currently: $PROJECT_ROOT"
echo "=================================================="
echo "      Initializing Kubernetes Master Node         "
echo "=================================================="
echo "Master Name:      $MASTER_NAME"
echo "Master IP:        $MASTER_IP"
echo "Pod Network CIDR: $POD_CIDR"
echo "Service CIDR:     $SVC_CIDR"
echo "=================================================="

# We define the check as a string of bash code to be sent into the VM
VM_HEALTH_CHECK=$(cat << 'EOF'
    # 1. Check Kubelet
    if ! sudo systemctl is-active --quiet kubelet; then exit 1; fi
    
    # 2. Check Admin Config
    if [ ! -f /etc/kubernetes/admin.conf ]; then exit 1; fi
    
    # 3. Check Certs
    if ! sudo kubeadm certs check-expiration >/dev/null 2>&1; then exit 1; fi
    
    # 4. Check API Response (3 attempts for cold starts)
    SUCCESS=1
    for i in {1..3}; do
        if sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes >/dev/null 2>&1; then
            SUCCESS=0; break
        fi
        sleep 2
    done
    if [ $SUCCESS -ne 0 ]; then exit 1; fi
    # 5. Check Static Pods
    if [ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then exit 1; fi
    
    exit 0
EOF
)


# ── IDEMPOTENCY GUARD ──────────────────────────────
# Run the health check inside the VM. If it exits 0,
# the cluster is already healthy — nothing to do.
# We temporarily disable set -e so a non-zero return
# from the health check doesn't kill this script before
# we can inspect the exit code ourselves.
echo "🩺 Running pre-flight health check on $MASTER_NAME..."

set +e
multipass exec "$MASTER_NAME" -- bash -c "$VM_HEALTH_CHECK"
HEALTH_EXIT_CODE=$?
set -e

if [ "$HEALTH_EXIT_CODE" -eq 0 ]; then
   echo "✅ Master is already healthy — skipping init."
   exit 0
fi

echo "⚠️  Health check failed (exit $HEALTH_EXIT_CODE) — proceeding with full init."
# ───────────────────────────────────────────────────


# Only then run kubeadm reset/init...
# 1. PRE-FLIGHT CLEANUP (The SRE Way)
# If a previous attempt failed, kubeadm will refuse to run.
# We force a reset to clear out the "ghosts" of previous failures.
echo "🧹 Cleaning up any previous Kubernetes state..."
multipass exec $MASTER_NAME -- sudo kubeadm reset -f || true
multipass exec $MASTER_NAME -- sudo rm -rf /etc/cni/net.d || true
multipass exec $MASTER_NAME -- sudo crictl pull registry.k8s.io/coredns/coredns:v1.10.1
# FIX: Use explicit path instead of $HOME which expands on the LOCAL machine
# and would delete your Mac's ~/.kube directory!
multipass exec $MASTER_NAME -- bash -c 'sudo rm -rf /home/ubuntu/.kube' || true
# 2. DISABLE SWAP (The #1 reason kubeadm fails)
echo "🚫 Ensuring Swap is disabled..."
multipass exec $MASTER_NAME -- sudo swapoff -a

# 3. INITIALIZE CLUSTER
# We use --ignore-preflight-errors to handle small resource inconsistencies
# that happen in virtualized environments.
echo "🚚 Phase 1: Pre-pulling Kubernetes images (Prevents 'Connection Reset' errors)..."
# We wrap this in a 3-attempt retry loop to handle transient network issues
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
  echo "   Attempt $i/$MAX_RETRIES: Pulling images..."
  if multipass exec $MASTER_NAME -- sudo kubeadm config images pull; then
    echo "   ✅ All images downloaded successfully."
    break
  else
    if [ $i -eq $MAX_RETRIES ]; then
      echo "   ❌ Failed to pull images after $MAX_RETRIES attempts. Check your internet connection."
      exit 1
    fi
    echo "   ⚠️  Pull failed (likely a network hiccup). Retrying in 10s..."
    sleep 10
  fi
done
echo "🚀 Phase 2: Running kubeadm init (Configuring the Control Plane)..." 
# Note: We keep the ignore-preflight-errors just in case your VM is slightly under-provisioned
multipass exec $MASTER_NAME -- sudo kubeadm init \
  --pod-network-cidr=$POD_CIDR \
  --service-cidr=$SVC_CIDR \
  --apiserver-advertise-address=$MASTER_IP \
  --ignore-preflight-errors=NumCPU,Mem
# Check if kubeadm init actually worked
if [ $? -ne 0 ]; then
  echo "❌ Error: kubeadm init failed during configuration!"
  exit 1
fi
echo "✅ Master Control Plane is initialized."

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

# 5c.1 AUTOMATIC KICKSTART (The Permanent Fix)
# Sometimes Kubelet misses the CNI file creation on initial boot.
# We proactively restart it to ensure it picks up the new Flannel config.
echo "🔄 Proactively restarting Kubelet and Containerd to pick up CNI..."
multipass exec $MASTER_NAME -- sudo systemctl restart containerd kubelet

# 5c.2 UNTAINT MASTER (Optional but recommended for single-node start)
# This allows CoreDNS to run on the master immediately so the 'wait' 
# command doesn't hang if workers haven't joined yet.
echo "🔓 Removing master taint to allow CoreDNS to schedule..."

set -x

multipass exec $MASTER_NAME -- kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
multipass exec $MASTER_NAME -- kubectl taint nodes --all node-role.kubernetes.io/master-        || true

set +x

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
# ==================================================
# 6. CAPTURE JOIN COMMAND (The Clean Way)
# ==================================================
echo "🔑 Generating join command for workers..."
# 1. Ensure the directory exists on your Mac/Host
mkdir -p "$PROJECT_ROOT/out"
# 2. Run the command in the VM, but stream the output 
#    directly into a file on your Mac.
#    Note: We use 'sudo' inside the exec to ensure kubeadm has permissions.
multipass exec $MASTER_NAME -- sudo kubeadm token create --print-join-command > "$PROJECT_ROOT/out/join-command.sh"
# 3. Make it executable on your Mac
chmod +x "$PROJECT_ROOT/out/join-command.sh"
echo "✅ Join command saved to $PROJECT_ROOT/out/join-command.sh"
echo "=================================================="
echo "✅ Master Initialization Complete!"
echo "=================================================="
