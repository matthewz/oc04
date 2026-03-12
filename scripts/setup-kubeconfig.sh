#!/bin/bash
set -e
# Arguments
MASTER_NAME="${1}"
MASTER_IP="${2}"
KUBECONFIG_NAME="${3:-config-k8s-multipass}"
echo "=================================================="
echo "Setting up Local Kubeconfig"
echo "=================================================="
echo "Master: ${MASTER_NAME}"
echo "Master IP: ${MASTER_IP}"
echo "Kubeconfig: ~/.kube/${KUBECONFIG_NAME}"
echo "=================================================="
# Create .kube directory if it doesn't exist
mkdir -p ~/.kube
# Copy kubeconfig from master
echo "📋 Copying kubeconfig from master..."
multipass exec ${MASTER_NAME} -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/${KUBECONFIG_NAME}
# Update server address to use master IP
echo "🔧 Updating server address..."
sed -i.bak "s|server: https://.*:6443|server: https://${MASTER_IP}:6443|" ~/.kube/${KUBECONFIG_NAME}
# Set proper permissions
chmod 600 ~/.kube/${KUBECONFIG_NAME}
echo "✅ Kubeconfig saved to: ~/.kube/${KUBECONFIG_NAME}"
echo ""
echo "To use this config, run:"
echo "  export KUBECONFIG=~/.kube/${KUBECONFIG_NAME}"
echo ""
echo "Or add to your shell profile:"
echo "  echo 'export KUBECONFIG=~/.kube/${KUBECONFIG_NAME}' >> ~/.bashrc"
echo ""
echo "Or merge with existing config:"
echo "  KUBECONFIG=~/.kube/config:~/.kube/${KUBECONFIG_NAME} kubectl config view --flatten > ~/.kube/config.new"
echo "  mv ~/.kube/config.new ~/.kube/config"
echo "=================================================="
