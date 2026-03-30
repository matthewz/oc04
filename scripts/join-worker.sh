#!/bin/bash
set -e
set -o pipefail
# Arguments passed from Terraform:
WORKER_NAME=$1  # e.g., k8s-worker1
MASTER_NAME=$2  # e.g., k8s-master
PROJECT_ROOT=$3 # e.g., ${path.module}
echo "=================================================="
echo "🔗 Preparing to join $WORKER_NAME to $MASTER_NAME..."
echo "=================================================="
# 1. Wait for Master API and Kubeadm to be ready
echo "⏳ Waiting for Master ($MASTER_NAME) to be ready..."
MAX_RETRIES=60
COUNT=0
# Loop until kubeadm is responsive on the master VM
until multipass exec "$MASTER_NAME" -- sudo kubeadm token list 2>/dev/null
do
    COUNT=$((COUNT+1))
    if [ $COUNT -gt $MAX_RETRIES ]; then
        echo "❌ Master not ready after 10 minutes. Exiting."
        exit 1
    fi
    echo "   Attempt $COUNT/$MAX_RETRIES: Master not ready yet, waiting 10s..."
    sleep 10
done
echo "✅ Master is ready."
# 2. Check if worker is already part of the cluster
# This prevents errors if you run the script twice
if multipass exec "$WORKER_NAME" -- sudo test -f /etc/kubernetes/kubelet.conf; then
    echo "✅ $WORKER_NAME is already part of a cluster. Skipping join."
    exit 0
fi
# 3. Generate a fresh join command from the Master VM
echo "🎟️  Requesting join token from Master..."
# We use -- (double dash) and tail -1 to get the exact command
JOIN_CMD=$(multipass exec "$MASTER_NAME" -- sudo kubeadm token create --print-join-command 2>/dev/null | tail -1)
# Validate that we actually received a 'kubeadm join' command
if [[ -z "$JOIN_CMD" || ! "$JOIN_CMD" == *"kubeadm join"* ]]; then
    echo "❌ Failed to retrieve join command from $MASTER_NAME. Exiting."
    exit 1
fi
echo "📋 Join command retrieved successfully."
# 4. Execute the join command inside the worker VM
echo "🚀 Joining $WORKER_NAME to the cluster..."
multipass exec "$WORKER_NAME" -- sudo bash -c "$JOIN_CMD"
echo "✅ $WORKER_NAME successfully joined!"
echo "=================================================="
