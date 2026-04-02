#!/bin/bash
set -e
set -o pipefail
WORKER_NAME=$1
MASTER_NAME=$2
PROJECT_ROOT=$3
echo "=================================================="
echo "🔗 Preparing to join $WORKER_NAME to $MASTER_NAME..."
echo "=================================================="
# 1. Wait for Master to be ready
echo "⏳ Waiting for Master ($MASTER_NAME) to be ready..."
MAX_RETRIES=60
COUNT=0
until multipass exec "$MASTER_NAME" -- sudo kubeadm token list 2>/dev/null; do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "❌ Master not ready after 10 minutes. Exiting."
        exit 1
    fi
    echo "   Attempt $COUNT/$MAX_RETRIES: Master not ready yet, waiting 10s..."
    sleep 10
done
echo "✅ Master is ready."
# 2. Only drain/delete if the node already exists in the cluster
echo "🧹 Checking for existing $WORKER_NAME registration..."
NODE_EXISTS=$(multipass exec "$MASTER_NAME" -- \
    sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf \
    get node "$WORKER_NAME" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NODE_EXISTS" -gt "0" ]; then
    echo "   Found existing node, draining and deleting..."
    multipass exec "$MASTER_NAME" -- \
        sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf \
        drain "$WORKER_NAME" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --timeout=30s 2>/dev/null || true
    multipass exec "$MASTER_NAME" -- \
        sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf \
        delete node "$WORKER_NAME" 2>/dev/null || true
    echo "   ✅ Existing node removed."
else
    echo "   ℹ️  No existing node found, skipping drain/delete."
fi
# 3. Reset kubeadm state on the worker
echo "🔄 Resetting $WORKER_NAME..."
multipass exec "$WORKER_NAME" -- sudo kubeadm reset -f
multipass exec "$WORKER_NAME" -- sudo rm -rf /etc/kubernetes /var/lib/kubelet
# 4. Generate a fresh join command from the Master
echo "🎟️  Requesting join token from Master..."
JOIN_CMD=$(multipass exec "$MASTER_NAME" -- sudo kubeadm token create --print-join-command 2>/dev/null | tail -1)
if [[ -z "$JOIN_CMD" || ! "$JOIN_CMD" == *"kubeadm join"* ]]; then
    echo "❌ Failed to retrieve join command from $MASTER_NAME. Exiting."
    exit 1
fi
echo "📋 Join command retrieved successfully."
# 5. Join the worker to the cluster
echo "🚀 Joining $WORKER_NAME to the cluster..."
multipass exec "$WORKER_NAME" -- sudo bash -c "$JOIN_CMD"
echo "✅ $WORKER_NAME successfully joined!"
echo "=================================================="
