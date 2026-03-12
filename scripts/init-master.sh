#!/bin/bash
set -e
# Arguments
MASTER_NAME="${1}"
MASTER_IP="${2}"
POD_NETWORK_CIDR="${3:-10.244.0.0/16}"
SERVICE_CIDR="${4:-10.96.0.0/12}"
OUTPUT_DIR="${5}"
echo "=================================================="
echo "Initializing Kubernetes Master"
echo "=================================================="
echo "Master Name: ${MASTER_NAME}"
echo "Master IP: ${MASTER_IP}"
echo "Pod Network CIDR: ${POD_NETWORK_CIDR}"
echo "Service CIDR: ${SERVICE_CIDR}"
echo "=================================================="
# Initialize Kubernetes master
echo "🚀 Running kubeadm init..."
multipass exec ${MASTER_NAME} -- bash -c "
set -e
set -x
sudo kubeadm init \
  --apiserver-advertise-address=${MASTER_IP} \
  --pod-network-cidr=${POD_NETWORK_CIDR} \
  --service-cidr=${SERVICE_CIDR} \
  --node-name=${MASTER_NAME}
set +x
echo '✅ kubeadm init complete!'
"
# Set up kubectl for the ubuntu user
echo "🔧 Setting up kubectl..."
multipass exec ${MASTER_NAME} -- bash -c "
set -e
set -x
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
set +x
echo '✅ kubectl configured!'
"
# Install Flannel CNI
echo "🌐 Installing Flannel CNI..."
multipass exec ${MASTER_NAME} -- bash -c "
set -e
set -x
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
set +x
echo '✅ Flannel CNI installed!'
"
# Generate join command
echo "📝 Generating join command..."
multipass exec ${MASTER_NAME} -- bash -c "
set -e
JOIN_COMMAND=\$(sudo kubeadm token create --print-join-command)
echo "JOIN_COMMAND=_${JOIN_COMMAND}_"
echo \"#!/bin/bash\" > /home/ubuntu/join-command.sh
echo \"set -e\" >> /home/ubuntu/join-command.sh
echo \"sudo \${JOIN_COMMAND}\" >> /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh
echo '✅ Join command generated!'
"
# Copy join command to local machine
echo "💾 Saving join command locally..."
multipass exec ${MASTER_NAME} -- cat /home/ubuntu/join-command.sh > "${OUTPUT_DIR}/scripts/join-command.sh"
chmod +x "${OUTPUT_DIR}/scripts/join-command.sh"
echo "✅ Master initialization complete!"
echo "=================================================="
