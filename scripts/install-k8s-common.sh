#!/bin/bash
# install-k8s-common.sh
# Usage: bash install-k8s-common.sh <node-name> <k8s-version>
# Example: bash install-k8s-common.sh k8s-master 1.28.0
set -e
# ─────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────
NODE_NAME="${1:?ERROR: NODE_NAME (arg 1) is required}"
K8S_VERSION="${2:?ERROR: K8S_VERSION (arg 2) is required}"
# Extract minor version: "1.28.0" → "1.28"
K8S_MINOR=$(echo "$K8S_VERSION" | cut -d'.' -f1-2 | sed 's/^v//')
# ─────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────
print_header() {
  echo "=================================================="
  echo "  Installing K8s Common Binaries on $NODE_NAME   "
  echo "=================================================="
}
wait_for_apt_locks() {
  multipass exec "$NODE_NAME" -- bash -c '
    echo "Waiting for apt locks to release..."
    RETRIES=30
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock      >/dev/null 2>&1; do
      RETRIES=$((RETRIES - 1))
      if [ "$RETRIES" -le 0 ]; then
        echo "❌ apt lock never released after 5 minutes. Aborting."
        exit 1
      fi
      echo "  ...apt is busy, waiting 10s... ($RETRIES retries left)"
      sleep 10
    done
    echo "✅ apt lock is free."
  '
}
install_prerequisites() {
  multipass exec "$NODE_NAME" -- bash -c '
    set -e
    echo "📦 Installing prerequisites..."
    sudo apt-get update -y
    sudo apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gpg \
      nfs-common \
      lsb-release
    echo "✅ Prerequisites installed."
  '
}
configure_kernel() {
  multipass exec "$NODE_NAME" -- bash -c '
    set -e
    echo "🔧 Configuring kernel modules..."
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
    echo "🔧 Configuring sysctl settings..."
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system
    echo "✅ Kernel configured."
  '
}
install_containerd() {
  # Passes ARCH into the remote shell as a positional arg ($1)
  # so we avoid relying on env injection across multipass exec.
  local ARCH
  ARCH=$(multipass exec "$NODE_NAME" -- dpkg --print-architecture)
  multipass exec "$NODE_NAME" -- bash -c '
    set -e
    ARCH="$1"
    echo "📦 Installing containerd 1.7.x from Docker repo..."
    # Add Dockers GPG key
    sudo mkdir -p -m 755 /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --batch --yes --no-tty --dearmor \
          -o /etc/apt/keyrings/docker.gpg
      echo "✅ Docker GPG key saved."
    else
      echo "✅ Docker GPG key already exists, skipping..."
    fi
    # Add Docker apt repo
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
      DISTRO=$(lsb_release -cs)
      echo \
        "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${DISTRO} stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list
      echo "✅ Docker apt source added."
    else
      echo "✅ Docker apt source already exists, skipping..."
    fi
    sudo apt-get update -y
    # Pin to 1.7.x — compatible with Kubernetes 1.28/1.29/1.30
    sudo apt-get install -y "containerd.io=1.7.*"
    # Generate default config and enable SystemdCgroup
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" \
      /etc/containerd/config.toml
    sudo systemctl restart containerd
    # Wait for the socket to be ready before returning
    echo "⏳ Waiting for containerd socket to be ready..."
    for i in $(seq 1 12); do
      if [ -S /var/run/containerd/containerd.sock ]; then
        echo "✅ containerd socket ready."
        break
      fi
      if [ "$i" -eq 12 ]; then
        echo "❌ containerd socket never appeared. Aborting."
        exit 1
      fi
      echo "   ...not ready yet, waiting 5s... (attempt $i/12)"
      sleep 5
    done
    echo "✅ Containerd 1.7.x configured."
  ' -- "$ARCH"
}
install_kubernetes_binaries() {
  echo "📦 Installing Kubernetes binaries (version ~${K8S_VERSION})..."
  # Pass K8S_MINOR and K8S_VERSION as positional args ($1, $2)
  # into the remote shell — no env injection, no heredoc quoting issues.
  multipass exec "$NODE_NAME" -- bash -c '
    set -e
    K8S_MINOR="$1"
    K8S_VERSION="$2"
    sudo mkdir -p -m 755 /etc/apt/keyrings
    # GPG key
    if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
      echo "📥 Downloading Kubernetes GPG key for v${K8S_MINOR}..."
      curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" | \
        sudo gpg --batch --yes --no-tty --dearmor \
          -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo "✅ GPG key saved."
    else
      echo "✅ Kubernetes GPG key already exists, skipping..."
    fi
    # Apt source
    if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]; then
      echo \
        "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" | \
        sudo tee /etc/apt/sources.list.d/kubernetes.list
      echo "✅ Kubernetes apt source added."
    else
      echo "✅ Kubernetes apt source already exists, skipping..."
    fi
    sudo apt-get update -y
    # Quote package specs so the shell does not glob-expand the *
    sudo apt-get install -y \
      "kubelet=${K8S_VERSION}*" \
      "kubeadm=${K8S_VERSION}*" \
      "kubectl=${K8S_VERSION}*"
    sudo apt-mark hold kubelet kubeadm kubectl
    echo "✅ Kubernetes binaries installed."
  ' -- "$K8S_MINOR" "$K8S_VERSION"
  #   ↑ "--" ends bash options; $1=K8S_MINOR $2=K8S_VERSION inside the script
}
# ─────────────────────────────────────────────
# Ensure the Multipass node exists and is running
# ─────────────────────────────────────────────
ensure_node_running() {
  echo "🔍 Checking Multipass node state for '$NODE_NAME'..."
  local MAX_ATTEMPTS=12   # how many times to poll after a start attempt
  local SLEEP_INTERVAL=15  # seconds between polls
  while true; do
    # ── 1. Does the node exist at all? ──────────────────────────────────────
    # `multipass info` exits non-zero if the instance doesn't exist.
    if ! multipass info "$NODE_NAME" >/dev/null 2>&1; then
      echo "❌ Node '$NODE_NAME' does not exist in Multipass."
      echo "   Please create it first (e.g. with multipass launch) and re-run."
      exit 1
    fi
    # ── 2. What state is it in? ──────────────────────────────────────────────
    # `multipass list` output looks like:
    #   k8s-master    Running    192.168.64.10   ...
    #   k8s-worker1   Stopped    --              ...
    #   k8s-worker2   Suspended  --              ...
    #
    # We grab the second whitespace-delimited field for our node.
    local STATE
    STATE=$(multipass list --format csv \
              | awk -F',' -v name="$NODE_NAME" \
                  'NR>1 && $1==name {gsub(/"/, "", $2); print $2}')
    echo "   └─ Current state: ${STATE:-<unknown>}"
    case "$STATE" in
      Running)
        echo "✅ Node '$NODE_NAME' is Running. Proceeding..."
        return 0
        ;;
      Stopped|Suspended)
        echo "▶️  Node '$NODE_NAME' is ${STATE}. Attempting to start..."
        # `multipass start` is idempotent — safe to call even if already starting.
        multipass start "$NODE_NAME"
        # ── 3. Poll until Running (or give up) ──────────────────────────────
        local ATTEMPT=0
        while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
          ATTEMPT=$((ATTEMPT + 1))
          sleep "$SLEEP_INTERVAL"
          local NEW_STATE
          NEW_STATE=$(multipass list --format csv \
                        | awk -F',' -v name="$NODE_NAME" \
                            'NR>1 && $1==name {gsub(/"/, "", $2); print $2}')
          echo "   └─ Waiting for Running... attempt ${ATTEMPT}/${MAX_ATTEMPTS}, state: ${NEW_STATE:-<unknown>}"
          if [ "$NEW_STATE" = "Running" ]; then
            echo "✅ Node '$NODE_NAME' is now Running."
            # Give SSH/cloud-init a moment to finish booting before we exec into it
            echo "⏳ Waiting 5s for SSH to stabilise..."
            sleep 15
            return 0
          fi
        done
        # If we exhausted retries, loop back to the top and re-evaluate state.
        # This handles edge cases like the node transitioning through intermediate
        # states (e.g. "Starting") that multipass occasionally surfaces.
        echo "⚠️  Node did not reach Running within $((MAX_ATTEMPTS * SLEEP_INTERVAL))s."
        echo "   Retrying outer loop..."
        ;;
      *)
        # Covers states like "Starting", "Restarting", "Deleted", or anything new.
        if [ -z "$STATE" ]; then
          echo "❌ Could not determine state for '$NODE_NAME'."
          echo "   Is 'multipass list' working correctly? Aborting."
          exit 1
        fi
        echo "⏳ Node is in state '${STATE}' — waiting ${SLEEP_INTERVAL}s and re-checking..."
        sleep "$SLEEP_INTERVAL"
        ;;
    esac
  done
}
# ─────────────────────────────────────────────
# Helper: run a multipass exec with a hard timeout
# Usage: multipass_exec_timeout <seconds> <node> -- <cmd...>
# Returns 1 on timeout or error instead of hanging forever.
# ─────────────────────────────────────────────
multipass_exec_timeout() {
  local TIMEOUT_SECS="$1"
  local NODE="$2"
  shift 2  # remaining args are: -- <cmd...>
  timeout "$TIMEOUT_SECS" multipass exec "$NODE" "$@"
  local EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "   └─ ⚠️  multipass exec timed out after ${TIMEOUT_SECS}s"
    return 1
  fi
  return "$EXIT_CODE"
}
check_node_health() {
  echo "🔍 Starting health check for $NODE_NAME..."
  local MAX_ATTEMPTS=10    # maximum number of polling attempts
  local SLEEP_INTERVAL=10  # seconds to wait between attempts
  local ATTEMPT=0
  local EXEC_TIMEOUT=15    # hard timeout (seconds) for any multipass exec call
  LOCAL_KUBECONFIG="$HOME/.kube/config-k8s-multipass"
  # ── Phase 1: kubeconfig missing — lightweight kubelet check ───────────────
  if [ ! -f "$LOCAL_KUBECONFIG" ]; then
    echo "api: ⚪ Local kubeconfig not found at $LOCAL_KUBECONFIG. Skipping API check."
    while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
      ATTEMPT=$((ATTEMPT + 1))
      echo "   └─ Kubelet check attempt ${ATTEMPT}/${MAX_ATTEMPTS}..."
      if multipass_exec_timeout "$EXEC_TIMEOUT" "$NODE_NAME" \
           -- systemctl is-active --quiet kubelet 2>/dev/null; then
        echo "svc: ✅ Kubelet is active. Assuming node is healthy — skipping install."
        exit 0
      fi
      if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
        echo "   └─ Kubelet not active yet. Waiting ${SLEEP_INTERVAL}s before retry..."
        sleep "$SLEEP_INTERVAL"
      fi
    done
    echo "svc: ⚪ Kubelet not active after ${MAX_ATTEMPTS} attempts."
    echo "      Proceeding with installation..."
    return 0
  fi
  # ── Phase 2: kubeconfig found — full cluster API check ────────────────────
  echo "api: 📡 Found kubeconfig. Checking cluster node status..."
  while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "   └─ API check attempt ${ATTEMPT}/${MAX_ATTEMPTS}..."
    NODE_READY_STATUS=$(
      KUBECONFIG="$LOCAL_KUBECONFIG" \
        kubectl get node "$NODE_NAME" \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
          --request-timeout=5s \
          2>/dev/null \
      || echo "Unknown"
    )
    echo "   └─ Node Ready status: '${NODE_READY_STATUS}'"
    # ── Happy path ─────────────────────────────────────────────────────────
    if [ "$NODE_READY_STATUS" = "True" ]; then
      echo "=================================================="
      echo "🎉 Cluster reports $NODE_NAME is Ready!"
      echo "=================================================="
      exit 0
    fi
    # ── API unreachable or node not joined ─────────────────────────────────
    # Do NOT retry kubectl — check kubelet binary with a hard timeout
    # so a flaky SSH connection cannot hang the script.
    if [ "$NODE_READY_STATUS" = "Unknown" ] || [ -z "$NODE_READY_STATUS" ]; then
      echo "api: ⚠️  API returned '${NODE_READY_STATUS:-empty}' — cluster unreachable or node not joined."
      echo "pkg: 🔍 Checking for kubelet binary (timeout ${EXEC_TIMEOUT}s)..."
      if ! multipass_exec_timeout "$EXEC_TIMEOUT" "$NODE_NAME" \
             -- which kubelet >/dev/null 2>&1; then
        echo "pkg: ⚪ Kubelet binary not found (or SSH timed out). Proceeding with fresh install..."
        return 0
      fi
      echo "pkg: ✅ Kubelet binary present but node not in cluster. Running setup..."
      return 0
    fi
    # ── Node in cluster but not Ready — worth retrying ─────────────────────
    if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
      echo "   └─ Node known to API but not Ready. Waiting ${SLEEP_INTERVAL}s before retry..."
      sleep "$SLEEP_INTERVAL"
    fi
  done
  # ── Exhausted retries ──────────────────────────────────────────────────────
  echo "=================================================="
  echo "⚠️  Node '$NODE_NAME' did not reach Ready status after"
  echo "    ${MAX_ATTEMPTS} attempts (~$((MAX_ATTEMPTS * SLEEP_INTERVAL))s)."
  echo "    Running setup anyway to attempt to restore consistency..."
  echo "=================================================="
  return 0
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
print_footer() {
  echo "✅ Common K8s setup complete for $NODE_NAME"
  echo "=================================================="
}
# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
  print_header
  ensure_node_running
  check_node_health
  wait_for_apt_locks
  install_prerequisites
  configure_kernel
  install_containerd
  install_kubernetes_binaries
  print_footer
}
main "$@"
