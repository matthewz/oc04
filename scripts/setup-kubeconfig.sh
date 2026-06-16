#!/bin/bash
set -e
# ─────────────────────────────────────────────────────────────────────────────
# setup-kubeconfig.sh
# Copies the kubeconfig from a kubeadm-initialised master VM (via multipass)
# to the local machine, patches the server address, and verifies connectivity.
#
# Usage: setup-kubeconfig.sh <master-name> <master-ip> [kubeconfig-name]
# ─────────────────────────────────────────────────────────────────────────────
# ── Constants ─────────────────────────────────────────────────────────────────
readonly KUBEADM_CONF="/etc/kubernetes/admin.conf"
readonly MAX_WAIT_KUBEADM=300   # seconds to wait for kubeadm init
readonly MAX_WAIT_API=120       # seconds to wait for API server
readonly POLL_INTERVAL=10       # seconds between each poll attempt
# ── Arguments (set once in parse_args, used everywhere) ───────────────────────
MASTER_NAME=""
MASTER_IP=""
KUBECONFIG_NAME=""
KUBECONFIG_PATH=""
# ─────────────────────────────────────────────────────────────────────────────
# print_header
#   Prints the opening banner with the resolved runtime values.
# ─────────────────────────────────────────────────────────────────────────────
print_header() {
  echo "=================================================="
  echo "       Setting up Local Kubeconfig                "
  echo "=================================================="
  echo "Master:     ${MASTER_NAME}"
  echo "Master IP:  ${MASTER_IP}"
  echo "Kubeconfig: ${KUBECONFIG_PATH}"
  echo "=================================================="
}
# ─────────────────────────────────────────────────────────────────────────────
# parse_args <master-name> <master-ip> [kubeconfig-name]
#   Populates globals and validates all inputs before any work is done.
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
  MASTER_NAME="${1:-}"
  MASTER_IP=$(get_node_ip "$MASTER_NAME")
  echo "📡 Resolved master IP: $MASTER_IP"
  KUBECONFIG_NAME="${3:-config-k8s-multipass}"
  KUBECONFIG_PATH="${HOME}/.kube/${KUBECONFIG_NAME}"
  if [ -z "$MASTER_NAME" ]; then
    echo "❌ Error: MASTER_NAME argument is required."
    echo "   Usage: $0 <master-name> <master-ip> [kubeconfig-name]"
    exit 1
  fi
  if [ -z "$MASTER_IP" ]; then
    echo "❌ Error: MASTER_IP argument is required."
    echo "   Usage: $0 <master-name> <master-ip> [kubeconfig-name]"
    exit 1
  fi
  if ! echo "$MASTER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ Error: MASTER_IP '${MASTER_IP}' does not look like a valid IP address."
    echo "   Check that ${MASTER_NAME} is running and that master-ip.txt was written correctly."
    exit 1
  fi
}
# ─────────────────────────────────────────────────────────────────────────────
# wait_for_kubeadm
#   Polls the master VM until /etc/kubernetes/admin.conf exists, which
#   indicates kubeadm init has completed. Exits with an error if the file
#   does not appear within MAX_WAIT_KUBEADM seconds.
# ─────────────────────────────────────────────────────────────────────────────
wait_for_kubeadm() {
  echo "⏳ Waiting for kubeadm init to complete on ${MASTER_NAME}..."
  local elapsed=0
  while true; do
    if multipass exec "${MASTER_NAME}" -- sudo test -f "${KUBEADM_CONF}" 2>/dev/null; then
      echo "✅ admin.conf found after ${elapsed}s — kubeadm init complete."
      return 0
    fi
    if [ "$elapsed" -ge "$MAX_WAIT_KUBEADM" ]; then
      echo "❌ Timed out after ${MAX_WAIT_KUBEADM}s waiting for kubeadm init."
      echo "   Check cloud-init logs with:"
      echo "   multipass exec ${MASTER_NAME} -- sudo cat /var/log/cloud-init-output.log"
      exit 1
    fi
    echo "   ⏳ Still waiting... (${elapsed}s elapsed)"
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
}
# ─────────────────────────────────────────────────────────────────────────────
# copy_kubeconfig
#   Ensures ~/.kube exists, then copies admin.conf from the master VM to the
#   local kubeconfig path. Validates the file is non-empty after the copy.
# ─────────────────────────────────────────────────────────────────────────────
copy_kubeconfig() {
  mkdir -p "${HOME}/.kube"
  echo "📋 Copying kubeconfig from ${MASTER_NAME}..."
  multipass exec "${MASTER_NAME}" -- sudo cat "${KUBEADM_CONF}" \
    > "${KUBECONFIG_PATH}"
  if [ ! -s "${KUBECONFIG_PATH}" ]; then
    echo "❌ Error: Kubeconfig file is empty or was not created."
    echo "   Check that kubeadm init completed successfully on ${MASTER_NAME}."
    exit 1
  fi
  echo "✅ Kubeconfig copied successfully."
}
# ─────────────────────────────────────────────────────────────────────────────
# patch_server_address
#   Replaces the server address written by kubeadm (typically 127.0.0.1 or
#   the internal hostname) with the actual VM IP so that a local kubectl can
#   reach the API server. Uses a .bak suffix for macOS sed compatibility.
# ─────────────────────────────────────────────────────────────────────────────
patch_server_address() {
  echo "🔧 Patching server address to https://${MASTER_IP}:6443..."
  sed -i.bak "s|server: https://.*:6443|server: https://${MASTER_IP}:6443|" \
    "${KUBECONFIG_PATH}"
  rm -f "${KUBECONFIG_PATH}.bak"
  local written_server
  written_server=$(grep "server:" "${KUBECONFIG_PATH}" | awk '{print $2}')
  echo "✅ Server address in kubeconfig: ${written_server}"
  if ! echo "$written_server" | grep -q "$MASTER_IP"; then
    echo "❌ Warning: Server address does not contain expected IP ${MASTER_IP}."
    echo "   You may need to manually edit ${KUBECONFIG_PATH}"
  fi
}
# ─────────────────────────────────────────────────────────────────────────────
# secure_kubeconfig
#   Locks down file permissions. Kubeconfig contains cluster credentials and
#   must never be world- or group-readable.
# ─────────────────────────────────────────────────────────────────────────────
secure_kubeconfig() {
  chmod 600 "${KUBECONFIG_PATH}"
  echo "🔒 Permissions set to 600 on ${KUBECONFIG_PATH}"
}
# ─────────────────────────────────────────────────────────────────────────────
# wait_for_api_server
#   Polls the Kubernetes API server using the freshly written kubeconfig.
#   Non-fatal — the kubeconfig is valid even if the API is slow to come up,
#   so we warn rather than exit on timeout.
# ─────────────────────────────────────────────────────────────────────────────
wait_for_api_server() {
  echo "⏳ Waiting for Kubernetes API server to respond..."
  local elapsed=0
  while true; do
    if kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes &>/dev/null; then
      echo "✅ API server is responding."
      return 0
    fi
    if [ "$elapsed" -ge "$MAX_WAIT_API" ]; then
      echo "⚠️  API server not responding after ${MAX_WAIT_API}s."
      echo "   The kubeconfig has been saved — try 'kubectl get nodes' manually once the cluster is ready."
      return 0   # non-fatal
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
}
# ─────────────────────────────────────────────────────────────────────────────
# print_usage_instructions
#   Prints the three standard ways to activate the new kubeconfig locally.
# ─────────────────────────────────────────────────────────────────────────────
print_usage_instructions() {
  echo ""
  echo "✅ Kubeconfig saved to: ${KUBECONFIG_PATH}"
  echo ""
  echo "=================================================="
  echo "  To use this cluster, run one of the following:  "
  echo "=================================================="
  echo ""
  echo "  # Option 1 — Export for this terminal session:"
  echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
  echo "  kubectl get nodes"
  echo ""
  echo "  # Option 2 — Add to your shell profile permanently:"
  echo "  echo 'export KUBECONFIG=${KUBECONFIG_PATH}' >> ~/.zshrc"
  echo ""
  echo "  # Option 3 — Merge with your existing ~/.kube/config:"
  echo "  KUBECONFIG=~/.kube/config:${KUBECONFIG_PATH} kubectl config view --flatten > ~/.kube/config.new"
  echo "  mv ~/.kube/config.new ~/.kube/config"
  echo ""
  echo "=================================================="
}
get_node_ip() {
  local NODE="$1"
  local IP
  IP=$(multipass info "$NODE" --format csv \
        | tail -1 \
        | awk -F',' '{print $3}' \
        | tr -d ' ')
  if [ -z "$IP" ]; then
    echo "❌ Could not resolve IP for node '$NODE'" >&2
    return 1
  fi
  echo "$IP"
}
# ─────────────────────────────────────────────────────────────────────────────
# main
#   Orchestrates all steps in dependency order:
#     1. parse & validate inputs
#     2. wait for kubeadm to finish on the VM
#     3. copy the kubeconfig locally
#     4. patch the server address to the real VM IP
#     5. lock down file permissions
#     6. verify the API server is reachable
#     7. print usage instructions
# ─────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  print_header
  wait_for_kubeadm
  copy_kubeconfig
  patch_server_address
  secure_kubeconfig
  wait_for_api_server
  print_usage_instructions
}
main "$@"
