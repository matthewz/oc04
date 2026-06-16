#!/bin/bash
set -e
set -o pipefail
set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/multipass.sh"
if [[ ! -f "$LIB" ]]; then
    echo "❌ Required library not found: $LIB"
    echo "   Expected at: $LIB"
    exit 1
fi
source "$LIB"
if command -v gtimeout &>/dev/null; then
    TIMEOUT=gtimeout
else
    TIMEOUT=timeout
fi
set +x
WORKER_NAME=$1
MASTER_NAME=$2
echo "=================================================="
echo "🔗 Preparing to join $WORKER_NAME to $MASTER_NAME..."
echo "=================================================="
# 1. Wait for Master to be ready
is_master_ready() {
    vm_exec "$MASTER_NAME" kubeadm token list
}
echo "⏳ Waiting for Master ($MASTER_NAME) to be ready..."
MAX_RETRIES=60
COUNT=0
until is_master_ready; do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "❌ Master not ready after 10 minutes. Exiting."
        exit 1
    fi
    echo "   Attempt $COUNT/$MAX_RETRIES: Master not ready yet, waiting 10s..."
    sleep 10
done
echo "✅ Master is ready."
# 2. Check if node already exists, drain and delete if so
echo "🔍 Checking if $WORKER_NAME already exists in the cluster..."
if kube_exec_quiet "$MASTER_NAME" get node "$WORKER_NAME" --request-timeout=10s; then
    echo "   Found existing node, draining and removing..."
    # Drain — evict pods gracefully
    # ✅ No redirect needed - $TIMEOUT wraps the whole thing, output is fine to show
    $TIMEOUT 120 kube_exec "$MASTER_NAME" drain "$WORKER_NAME" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --timeout=120s || true
    # Strip any finalizers that might block deletion
    echo "   Removing any finalizers on $WORKER_NAME..."
    # ✅ Use kube_exec_quiet instead of 2>/dev/null
    kube_exec_quiet "$MASTER_NAME" patch node "$WORKER_NAME" \
        -p '{"metadata":{"finalizers":[]}}' \
        --type=merge || true
    # Delete with --wait=false so the script cannot hang here
    echo "   Deleting node object..."
    # ✅ Use kube_exec_quiet instead of 2>/dev/null
    kube_exec_quiet "$MASTER_NAME" delete node "$WORKER_NAME" \
        --force \
        --grace-period=0 \
        --wait=false || true
    sleep 5
    echo "   ✅ Existing node removed."
else
    echo "   ℹ️  No existing node found, skipping drain/delete."
fi

# 3. Reset kubeadm state on the worker
echo "🔄 Resetting $WORKER_NAME kubeadm state..."
###
vm_exec "$WORKER_NAME" bash -c "
  kubeadm reset -f
  rm -rf /var/lib/kubelet
  mkdir -p /etc/kubernetes/manifests
"
###
echo "   ✅ kubeadm reset complete."

# 4. Clean up stale CNI and network state
echo "🧹 Cleaning up stale CNI and network interfaces on $WORKER_NAME..."
vm_exec "$WORKER_NAME" bash -c '
    systemctl stop kubelet 2>/dev/null || true
    echo "   Removing stale CNI config and data..."
    rm -rf /var/lib/cni/
    rm -rf /etc/cni/net.d/
    rm -rf /var/lib/flannel/
    rm -f /run/flannel/subnet.env
    echo "   Removing stale network interfaces..."
    for iface in cni0 flannel.1 dummy0 kube-ipvs0; do
        if ip link show "$iface" &>/dev/null; then
            ip link set "$iface" down
            ip link delete "$iface"
            echo "   Deleted interface: $iface"
        fi
    done
    echo "   Flushing iptables rules..."
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X
    if command -v ipvsadm &>/dev/null; then
        ipvsadm --clear
    fi
    echo "   ✅ CNI and network cleanup complete."
'
set +x
# 4b. Verify CNI interfaces are actually gone before proceeding
cni0_is_gone() {
    ! vm_exec_quiet "$WORKER_NAME" ip link show cni0
}
echo "🔍 Verifying CNI interfaces are cleared on $WORKER_NAME..."
MAX_RETRIES=10
COUNT=0
until cni0_is_gone; do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "❌ cni0 still exists after cleanup on $WORKER_NAME."
        echo "   Try manually: multipass exec $WORKER_NAME -- sudo ip link delete cni0"
        exit 1
    fi
    echo "   Waiting for cni0 to clear... ($COUNT/$MAX_RETRIES)"
    sleep 3
done
echo "   ✅ CNI interfaces cleared. Safe to join."
# 5. Generate a fresh join command from the Master
echo "🎟️  Requesting join token from Master..."
# ✅ Capture into variable safely - no 2>/dev/null on the multipass call itself
JOIN_CMD=$(vm_exec "$MASTER_NAME" kubeadm token create --print-join-command | tail -1)
if [[ -z "$JOIN_CMD" || ! "$JOIN_CMD" == *"kubeadm join"* ]]; then
    echo "❌ Failed to retrieve join command from $MASTER_NAME. Exiting."
    exit 1
fi
echo "📋 Join command retrieved successfully."
# 6. Join the worker to the cluster
echo "🚀 Joining $WORKER_NAME to the cluster..."
vm_exec "$WORKER_NAME" bash -c "$JOIN_CMD"
echo "✅ $WORKER_NAME successfully joined!"

###
# After the join...
echo "⏳ Waiting for CNI config to appear on $WORKER_NAME..."
MAX_RETRIES=30
COUNT=0
until vm_exec_quiet "$WORKER_NAME" test -f /etc/cni/net.d/10-flannel.conflist; do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "❌ CNI config never appeared on $WORKER_NAME"
        echo "   Check: kubectl get pods -n kube-flannel -o wide"
        exit 1
    fi
    echo "   Waiting for Flannel to initialize CNI... ($COUNT/$MAX_RETRIES)"
    sleep 10
done
###
echo "✅ CNI config found. Flannel is initialized."
# Then restart kubelet so it picks up the now-present CNI config
echo "🔄 Restarting kubelet to pick up CNI config..."
vm_exec "$WORKER_NAME" systemctl restart kubelet
###

# 7. Verify the node appears as Ready in the cluster
node_is_ready() {
    local status
    status=$(kube_get "$MASTER_NAME" node "$WORKER_NAME")
    echo "$status" | grep -q "Ready"
}
echo "⏳ Waiting for $WORKER_NAME to appear as Ready..."
MAX_RETRIES=30
COUNT=0
until node_is_ready; do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "⚠️  $WORKER_NAME joined but not Ready after 5 minutes."
        echo "   Check: kubectl get nodes && kubectl get pods -n kube-flannel"
        break
    fi
    echo "   Attempt $COUNT/$MAX_RETRIES: Node not Ready yet, waiting 10s..."
    sleep 10
done
###
# 8. Kick containerd first, THEN kubelet after CNI is confirmed ready
echo "🔄 Restarting containerd on $WORKER_NAME to pick up CNI config..."
vm_exec "$WORKER_NAME" sudo systemctl restart containerd
sleep 10
echo "🔄 Restarting kubelet on $WORKER_NAME..."
vm_exec "$WORKER_NAME" sudo systemctl restart kubelet
sleep 10
echo "=================================================="
echo "✅ $WORKER_NAME is Ready!"
echo "=================================================="
