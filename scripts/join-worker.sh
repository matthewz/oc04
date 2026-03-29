#!/bin/bash
set -e
WORKER_NAME=$1
MASTER_NAME=$2
echo "🔗 Preparing to join $WORKER_NAME to $MASTER_NAME..."
# 1. Wait for Master API and Kubeadm to be ready
echo "⏳ Waiting for Master ($MASTER_NAME) to be ready..."
MAX_RETRIES=30
COUNT=0
until multipass exec "$MASTER_NAME" -- sudo kubeadm token list >/dev/null 2>&1
do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Master not ready after 5 minutes. Exiting."
        exit 1
    fi
    echo "Master not ready yet... (Attempt $((COUNT+1))/$MAX_RETRIES)"
    sleep 10
    COUNT=$((COUNT+1))
done
# 2. Check if already joined
if multipass exec "$WORKER_NAME" -- [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "✅ $WORKER_NAME is already part of a cluster. Skipping join."
    exit 0
fi
# 3. Generate a fresh join command from the Master
echo "🎟️ Requesting join token from Master..."
JOIN_CMD=$(multipass exec "$MASTER_NAME" -- sudo kubeadm token create --print-join-command)
# 4. Execute the join on the worker
echo "🚀 Joining $WORKER_NAME to the cluster..."
multipass exec "$WORKER_NAME" -- sudo bash -c "$JOIN_CMD"
echo "✅ $WORKER_NAME successfully joined!"
