#!/bin/bash
set -e
# Arguments
WORKER_NAME=$1
MASTER_IP=$2
PROJECT_ROOT=$3
echo "=================================================="
echo "      Initializing Kubernetes Worker Node         "
echo "=================================================="
echo "Worker Name:  $WORKER_NAME"
echo "Master IP:    $MASTER_IP"
echo "Project Root: $PROJECT_ROOT"
echo "=================================================="
# 1. PRE-FLIGHT CLEANUP
echo "🧹 Cleaning up any previous Kubernetes state on $WORKER_NAME..."
multipass exec $WORKER_NAME -- sudo kubeadm reset -f || true
multipass exec $WORKER_NAME -- sudo rm -rf /etc/cni/net.d || true
# 2. DISABLE SWAP
echo "🚫 Ensuring Swap is disabled..."
multipass exec $WORKER_NAME -- sudo swapoff -a
# 3. WAIT FOR JOIN COMMAND FROM MASTER
# We check for the file on the Mac (PROJECT_ROOT/out/join-command.sh)
# because the Master script now "transfers" it there.
echo "⏳ Waiting for Master to provide join command..."
JOIN_CMD_FILE="$PROJECT_ROOT/out/join-command.sh"
# INCREASED FROM 30 TO 60 (10 minutes total)
for i in {1..60}; do
  if [ -f "$JOIN_CMD_FILE" ]; then
    echo "✅ Join command found after $i attempts!"
    break
  fi
  
  if [ $i -eq 60 ]; then
    echo "❌ Error: Master join command not found after 10 minutes."
    echo "   Check if the Master initialization failed or if"
    echo "   $JOIN_CMD_FILE exists on your Mac."
    exit 1
  fi
  echo "   Attempt $i/60: Master not ready yet, waiting 10s..."
  sleep 10
done
# 4. READ THE COMMAND FROM THE FILE
# We read the file on the Mac and prepare it to run inside the VM
JOIN_COMMAND=$(cat "$JOIN_CMD_FILE")
# 5. EXECUTE JOIN COMMAND ON WORKER
echo "🚀 Joining worker node to the cluster..."
# We use 'bash -c' to ensure the command string is parsed correctly inside the VM
multipass exec $WORKER_NAME -- sudo bash -c "$JOIN_COMMAND"
echo "✅ Worker $WORKER_NAME joined successfully!"
echo "=================================================="
