#!/bin/bash
set -e
# Arguments
MASTER_NAME="${1}"
MASTER_IP="${2}"
KUBECONFIG_NAME="${3:-config-k8s-multipass}"
echo "=================================================="
echo "       Setting up Local Kubeconfig                "
echo "=================================================="
echo "Master:     ${MASTER_NAME}"
echo "Master IP:  ${MASTER_IP}"
echo "Kubeconfig: ~/.kube/${KUBECONFIG_NAME}"
echo "=================================================="
# Validate arguments — fail early with a clear message rather than
# producing a broken kubeconfig file with missing fields.
if [ -z "$MASTER_NAME" ]; then
  echo "❌ Error: MASTER_NAME argument is required."
  exit 1
fi
if [ -z "$MASTER_IP" ]; then
  echo "❌ Error: MASTER_IP argument is required."
  exit 1
fi
# Validate MASTER_IP looks like an actual IP address
if ! echo "$MASTER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "❌ Error: MASTER_IP '${MASTER_IP}' does not look like a valid IP address."
  echo "   Check that ${MASTER_NAME} is running and that master-ip.txt was written correctly."
  exit 1
fi
# Create .kube directory if it doesn't exist
mkdir -p ~/.kube
# Copy kubeconfig from master
# We read from /etc/kubernetes/admin.conf which is the canonical cluster
# admin config written by kubeadm during init.
echo "📋 Copying kubeconfig from master..."
multipass exec "${MASTER_NAME}" -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/${KUBECONFIG_NAME}
# Validate the file was actually written and is non-empty
if [ ! -s ~/.kube/${KUBECONFIG_NAME} ]; then
  echo "❌ Error: Kubeconfig file is empty or was not created."
  echo "   Check that kubeadm init completed successfully on ${MASTER_NAME}."
  exit 1
fi
# Update the server address to use the real VM IP instead of the default
# 127.0.0.1 or internal address that kubeadm writes into admin.conf.
# Without this your local kubectl cannot reach the API server.
# FIX: Use a platform-safe sed invocation. macOS sed requires the backup
# extension to be directly adjacent to -i with no space (i.e., -i.bak
# not -i .bak). We remove the .bak file afterwards to keep things clean.
echo "🔧 Updating server address to ${MASTER_IP}..."
sed -i.bak "s|server: https://.*:6443|server: https://${MASTER_IP}:6443|" \
  ~/.kube/${KUBECONFIG_NAME}
rm -f ~/.kube/${KUBECONFIG_NAME}.bak
# Set proper permissions — kubeconfig contains cluster credentials so
# it should never be world or group readable.
chmod 600 ~/.kube/${KUBECONFIG_NAME}
# Verify the server line was actually updated
WRITTEN_SERVER=$(grep "server:" ~/.kube/${KUBECONFIG_NAME} | awk '{print $2}')
echo "✅ Server address in kubeconfig: ${WRITTEN_SERVER}"
if ! echo "$WRITTEN_SERVER" | grep -q "$MASTER_IP"; then
  echo "❌ Warning: Server address does not contain expected IP ${MASTER_IP}."
  echo "   You may need to manually edit ~/.kube/${KUBECONFIG_NAME}"
fi
echo ""
echo "✅ Kubeconfig saved to: ~/.kube/${KUBECONFIG_NAME}"
echo ""
echo "=================================================="
echo "  To use this cluster, run one of the following:  "
echo "=================================================="
echo ""
echo "  # Option 1 — Export for this terminal session:"
echo "  export KUBECONFIG=~/.kube/${KUBECONFIG_NAME}"
echo "  kubectl get nodes"
echo ""
echo "  # Option 2 — Add to your shell profile permanently:"
echo "  echo 'export KUBECONFIG=~/.kube/${KUBECONFIG_NAME}' >> ~/.zshrc"
echo ""
echo "  # Option 3 — Merge with your existing ~/.kube/config:"
echo "  KUBECONFIG=~/.kube/config:~/.kube/${KUBECONFIG_NAME} kubectl config view --flatten > ~/.kube/config.new"
echo "  mv ~/.kube/config.new ~/.kube/config"
echo ""
echo "=================================================="
