#!/bin/bash
set -e
# Arguments
WORKER_NAME="${1}"
MASTER_NAME="${2}"
echo "=================================================="
echo "Joining Worker to Cluster"
echo "=================================================="
echo "Worker: ${WORKER_NAME}"
echo "Master: ${MASTER_NAME}"
echo "=================================================="
# Get the join command from master
echo "📋 Getting join command from master..."
JOIN_COMMAND=$(multipass exec ${MASTER_NAME} -- sudo kubeadm token create --print-join-command)
echo "JOIN_COMMAND=_${JOIN_COMMAND}_"
if [ -z "${JOIN_COMMAND}" ]; then
  echo "❌ Error: Failed to get join command"
  exit 1
fi

echo "🔗 Joining worker to cluster..."
multipass exec ${WORKER_NAME} -- bash -c "
set -e
set -x
sudo ${JOIN_COMMAND}
set +x
echo '✅ Successfully joined cluster!'
"

echo "Wait a bit for the node to register..."
set -x
sleep 10
set +x

echo "🔍 Verifying node registration..."
if multipass exec ${MASTER_NAME} -- kubectl get nodes | grep -q "${WORKER_NAME}"; then
  echo "✅ ${WORKER_NAME} successfully joined the cluster!"
else
  echo "⚠️  Warning: ${WORKER_NAME} may not have joined yet. Check with 'kubectl get nodes'"
fi
echo "=================================================="
