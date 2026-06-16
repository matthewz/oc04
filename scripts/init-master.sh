#!/bin/bash
set -e
# =============================================================================
# init-master.sh
# Initialises a kubeadm-based Kubernetes master node running inside a
# Multipass VM. Idempotent — a healthy cluster is detected and skipped.
#
# Usage: init-master.sh <master-name> <master-ip> <pod-cidr> <svc-cidr> <project-root>
# =============================================================================
# ── Constants ─────────────────────────────────────────────────────────────────
readonly FLANNEL_MANIFEST="https://raw.githubusercontent.com/flannel-io/flannel/v0.22.3/Documentation/kube-flannel.yml"
readonly MAX_IMAGE_RETRIES=3
readonly IMAGE_RETRY_DELAY=10       # seconds between image pull retries
readonly FLANNEL_POD_TIMEOUT=300s
readonly NODE_READY_TIMEOUT=600s
readonly CNI_BINARY_PATH="/opt/cni/bin/flannel"
readonly CNI_CONFIG_PATH="/etc/cni/net.d/10-flannel.conflist"
readonly CNI_ARTIFACT_MAX_WAITS=24  # 24 × 5s = 2 minutes
readonly CNI_ARTIFACT_WAIT=5        # seconds between each artifact poll
# ── Arguments (populated by parse_args, read everywhere else) ─────────────────
MASTER_NAME=""
MASTER_IP=""
POD_CIDR=""
SVC_CIDR=""
PROJECT_ROOT=""
# =============================================================================
# print_header
# =============================================================================
print_header() {
  echo "=================================================="
  echo "      Initializing Kubernetes Master Node         "
  echo "=================================================="
  echo "Master Name:      $MASTER_NAME"
  echo "Master IP:        $MASTER_IP"
  echo "Pod Network CIDR: $POD_CIDR"
  echo "Service CIDR:     $SVC_CIDR"
  echo "Project Root:     $PROJECT_ROOT"
  echo "=================================================="
}
# =============================================================================
# parse_args <master-name> <master-ip> <pod-cidr> <svc-cidr> <project-root>
#   Validates all inputs before any work is done.
# =============================================================================
parse_args() {
  if [ "$#" -lt 4 ]; then
    echo "❌ Error: Expected 4 arguments, got $#."
    echo "   Usage: $0 <master-name> <master-ip> <pod-cidr> <svc-cidr> <project-root>"
    exit 1
  fi

  MASTER_NAME="${1:?Usage: init-master.sh <master-name> <pod-cidr> <svc-cidr> <project-root>}"
  POD_CIDR="${2:?}"
  SVC_CIDR="${3:?}"
  PROJECT_ROOT="${4:?}"
  # Resolve IP live — never trust what Terraform cached at plan time
  MASTER_IP=$(get_node_ip "$MASTER_NAME")
  echo "📡 Resolved master IP: $MASTER_IP"
  if [ -z "$MASTER_NAME" ]; then
    echo "❌ Error: MASTER_NAME is required."
    exit 1
  fi
  if ! echo "$MASTER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ Error: MASTER_IP '${MASTER_IP}' is not a valid IPv4 address."
    exit 1
  fi
  if [ ! -d "$PROJECT_ROOT" ]; then
    echo "❌ Error: PROJECT_ROOT '${PROJECT_ROOT}' does not exist or is not a directory."
    exit 1
  fi
}
run_health_check() {
  multipass exec "$MASTER_NAME" -- bash -c '
    # 1. Kubelet must be active
    if ! sudo systemctl is-active --quiet kubelet; then
      echo "   health: kubelet not active"
      exit 1
    fi
    # 2. admin.conf must exist
    if [ ! -f /etc/kubernetes/admin.conf ]; then
      echo "   health: admin.conf missing"
      exit 1
    fi
    # 3. Certificates must be valid
    if ! sudo kubeadm certs check-expiration >/dev/null 2>&1; then
      echo "   health: certs check failed"
      exit 1
    fi
    # 4. API server must respond (3 attempts for cold starts)
    API_OK=1
    for i in 1 2 3; do
      if sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes >/dev/null 2>&1; then
        API_OK=0
        break
      fi
      sleep 2
    done
    if [ "$API_OK" -ne 0 ]; then
      echo "   health: API server not responding"
      exit 1
    fi
    # 5. Static pod manifests must exist
    if [ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
      echo "   health: kube-apiserver.yaml manifest missing"
      exit 1
    fi
    exit 0
  '
}
check_idempotency() {
  echo "🩺 Checking if $MASTER_NAME is already initialized..."
  if ! multipass info "$MASTER_NAME" >/dev/null 2>&1; then
    echo "❌ Error: VM '$MASTER_NAME' does not exist or is not running."
    exit 1
  fi
  if run_health_check; then
    echo "✅ Master is already healthy — skipping init."
    exit 0   
  else
    echo "⚠️  Health check failed — proceeding with cluster initialization..."
  fi
}
# =============================================================================
# reset_previous_state
#   Clears any leftovers from a previous failed kubeadm init so the fresh
#   init does not trip over stale state.
# =============================================================================
reset_previous_state() {
  echo "🧹 Cleaning up any previous Kubernetes state..."
  multipass exec "$MASTER_NAME" -- sudo kubeadm reset -f --cleanup-tmp-dir || true
  multipass exec "$MASTER_NAME" -- sudo rm -rf /etc/cni/net.d              || true
  multipass exec "$MASTER_NAME" -- bash -c 'sudo rm -rf /home/ubuntu/.kube' || true
}
# =============================================================================
# disable_swap
#   Swap must be off for kubelet to start. Cloud-init usually handles this
#   but we enforce it here to be safe.
# =============================================================================
disable_swap() {
  echo "🚫 Ensuring swap is disabled..."
  multipass exec "$MASTER_NAME" -- sudo swapoff -a
}
# =============================================================================
# pull_control_plane_images
#   Pre-pulls all kubeadm control-plane images with retry logic.
#   Doing this before `kubeadm init` prevents cryptic "connection reset"
#   errors caused by a pull timing out mid-init.
# =============================================================================
pull_control_plane_images() {
  echo "📥 Pre-pulling Kubernetes control plane images..."
  local attempt
  for attempt in $(seq 1 "$MAX_IMAGE_RETRIES"); do
    echo "   Attempt $attempt/$MAX_IMAGE_RETRIES..."
    if multipass exec "$MASTER_NAME" -- sudo kubeadm config images pull; then
      echo "   ✅ All images pulled successfully."
      return 0
    fi
    if [ "$attempt" -eq "$MAX_IMAGE_RETRIES" ]; then
      echo "   ❌ Failed to pull images after $MAX_IMAGE_RETRIES attempts."
      echo "      Check the VM's internet connectivity and DNS."
      exit 1
    fi
    echo "   ⚠️  Pull failed — retrying in ${IMAGE_RETRY_DELAY}s..."
    sleep "$IMAGE_RETRY_DELAY"
  done
}
# =============================================================================
# configure_kubectl_in_vm
#   Copies admin.conf into the ubuntu user's home so that plain `kubectl`
#   commands work inside the VM without sudo.
# =============================================================================
configure_kubectl_in_vm() {
  echo "⚙️  Configuring kubectl for the ubuntu user inside the VM..."
  multipass exec "$MASTER_NAME" -- bash -c '
    mkdir -p /home/ubuntu/.kube
    sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    sudo chown $(id -u ubuntu):$(id -g ubuntu) /home/ubuntu/.kube/config
  '
}
# =============================================================================
# wait_for_api_server
#   Polls until the API server responds before we try to talk to it.
#   Right after kubeadm init the API server needs a moment to warm up.
# =============================================================================
wait_for_api_server() {
  echo "⏳ Waiting for API server to become responsive..."
  multipass exec "$MASTER_NAME" -- bash -c '
    for i in $(seq 1 30); do
      if kubectl --request-timeout=5s get nodes >/dev/null 2>&1; then
        echo "   ✅ API server is responsive."
        exit 0
      fi
      echo "   attempt $i/30 — API server not ready yet, waiting 5s..."
      sleep 5
    done
    echo "❌ API server never became responsive after 150s."
    exit 1
  '
}
# =============================================================================
# install_flannel
#   Applies the Flannel CNI manifest. Checks first so the apply is idempotent
#   on re-runs. Uses --request-timeout to prevent hanging if the API server
#   is slow to respond right after kubeadm init.
# =============================================================================
install_flannel() {
  local MAX_WAITS=12
  local WAIT=5
  local attempt=0
  local flannel_exists=""
  echo "🌐 Checking Flannel installation..."
  # ── Step 1: Poll until the DaemonSet check returns a real answer ─────────────
  while [ "$attempt" -lt "$MAX_WAITS" ]; do
    attempt=$(( attempt + 1 ))
    local CHECK_CMD="kubectl --request-timeout=10s get ds -n kube-flannel kube-flannel-ds --no-headers"
    echo "   [attempt $attempt/$MAX_WAITS] Running: $CHECK_CMD"
    flannel_exists=$(multipass exec "$MASTER_NAME" -- bash -c "$CHECK_CMD 2>/dev/null" || true)
    if [ -n "$flannel_exists" ]; then
      echo "   ✅ Flannel DaemonSet already exists — skipping apply."
      return 0
    fi
    # A blank result means either "not installed" or "API not ready yet".
    # We disambiguate by checking whether the kube-flannel namespace exists.
    local NS_CMD="kubectl --request-timeout=10s get namespace kube-flannel --no-headers"
    echo "   [attempt $attempt/$MAX_WAITS] Running: $NS_CMD"
    local ns_exists
    ns_exists=$(multipass exec "$MASTER_NAME" -- bash -c "$NS_CMD 2>/dev/null" || true)
    if [ -z "$ns_exists" ]; then
      # Namespace absent → Flannel has never been installed → safe to apply.
      echo "   Flannel not found — proceeding with install."
      break
    fi
    # Namespace exists but DaemonSet not yet visible → API still warming up.
    echo "   ⏳ API server not ready yet — waiting ${WAIT}s..."
    sleep "$WAIT"
  done
  if [ "$attempt" -ge "$MAX_WAITS" ]; then
    echo "❌ Flannel check timed out after $(( MAX_WAITS * WAIT ))s."
    exit 1
  fi
  # ── Step 2: Apply the Flannel manifest ───────────────────────────────────────
  local APPLY_CMD="kubectl --request-timeout=30s apply -f $FLANNEL_MANIFEST"
  echo "   Running: $APPLY_CMD"
  local apply_result
  apply_result=$(multipass exec "$MASTER_NAME" -- bash -c "$APPLY_CMD 2>&1")
  local apply_exit=$?
  echo "$apply_result"
  if [ "$apply_exit" -ne 0 ]; then
    echo "❌ Flannel apply failed (exit $apply_exit)."
    exit 1
  fi
  echo "   ✅ Flannel applied successfully."
}
# =============================================================================
# wait_for_flannel_pod
#   Three-stage wait that mirrors what actually has to happen inside the pod:
#
#   Stage 1 — Pod scheduled        (DaemonSet creates the pod object)
#   Stage 2 — Init containers done (install-cni-plugin and install-cni must
#                                   complete before the main container starts;
#                                   this is when CNI artifacts are written)
#   Stage 3 — Pod Ready            (main flanneld container is running)
#
#   Splitting stage 2 out explicitly is the fix for the race where
#   verify_cni_artifacts() ran immediately after kubectl wait --for=ready
#   and found the files missing because the init containers had not yet
#   finished copying to the host.
# =============================================================================
wait_for_flannel_pod() {
  # ── Stage 1: Pod object exists ───────────────────────────────────────────────
  echo "⏳ [Stage 1/3] Waiting for Flannel pod to be scheduled (up to 2 minutes)..."
  multipass exec "$MASTER_NAME" -- bash -c '
    for i in $(seq 1 24); do
      COUNT=$(kubectl get pods -n kube-flannel \
        --selector=app=flannel \
        --no-headers 2>/dev/null | wc -l)
      if [ "$COUNT" -gt 0 ]; then
        echo "   ✅ Flannel pod scheduled (attempt $i)."
        exit 0
      fi
      echo "   attempt $i/24 — not yet scheduled, waiting 5s..."
      sleep 5
    done
    echo "❌ Flannel pod never appeared after 2 minutes."
    kubectl describe daemonset kube-flannel-ds -n kube-flannel
    exit 1
  '
  # ── Stage 2: Init containers completed ───────────────────────────────────────
  # The two init containers run sequentially before flanneld starts:
  #   install-cni-plugin  → cp /flannel        /opt/cni/bin/flannel
  #   install-cni         → cp cni-conf.json   /etc/cni/net.d/10-flannel.conflist
  # We poll jsonpath for each container's state rather than relying on the
  # pod-level Ready condition, which only reflects the main container.
  echo "⏳ [Stage 2/3] Waiting for Flannel init containers to complete (up to 2 minutes)..."
  multipass exec "$MASTER_NAME" -- bash -c '
    for i in $(seq 1 24); do
      # jsonpath returns "true" once a container has run to completion
      PLUGIN_DONE=$(kubectl get pods -n kube-flannel \
        --selector=app=flannel \
        -o jsonpath="{.items[0].status.initContainerStatuses[?(@.name==\"install-cni-plugin\")].state.terminated.exitCode}" \
        2>/dev/null || true)
      CNI_DONE=$(kubectl get pods -n kube-flannel \
        --selector=app=flannel \
        -o jsonpath="{.items[0].status.initContainerStatuses[?(@.name==\"install-cni\")].state.terminated.exitCode}" \
        2>/dev/null || true)
      if [ "$PLUGIN_DONE" = "0" ] && [ "$CNI_DONE" = "0" ]; then
        echo "   ✅ Both init containers completed successfully (attempt $i)."
        exit 0
      fi
      echo "   attempt $i/24 — install-cni-plugin=${PLUGIN_DONE:-pending}, install-cni=${CNI_DONE:-pending}, waiting 5s..."
      sleep 5
    done
    echo "❌ Init containers did not complete after 2 minutes. Dumping pod status:"
    kubectl get pods -n kube-flannel --selector=app=flannel -o wide
    kubectl describe pods -n kube-flannel --selector=app=flannel
    exit 1
  '
  # ── Stage 3: Pod Ready ────────────────────────────────────────────────────────
  # Now that the init containers have finished writing CNI artifacts to the host
  # we can safely wait for the main flanneld container to reach Ready.
  echo "⏳ [Stage 3/3] Waiting for Flannel pod to reach Ready (up to 5 minutes)..."
  multipass exec "$MASTER_NAME" -- \
    kubectl wait --namespace kube-flannel \
      --for=condition=ready pod \
      --selector=app=flannel \
      --timeout="$FLANNEL_POD_TIMEOUT"
  echo "   ✅ Flannel pod is Ready."
}
# =============================================================================
# verify_cni_artifacts
#   Confirms that Flannel's init containers wrote the CNI binary and config
#   to the host. Polls rather than checking once — on a slow or loaded VM
#   the files can lag a few seconds behind the init container exit code.
#
#   Artifact sources (from the DaemonSet manifest):
#     install-cni-plugin: cp /flannel              → /opt/cni/bin/flannel
#     install-cni:        cp cni-conf.json         → /etc/cni/net.d/10-flannel.conflist
#
#   Constants CNI_BINARY_PATH, CNI_CONFIG_PATH, CNI_ARTIFACT_MAX_WAITS and
#   CNI_ARTIFACT_WAIT are declared at the top of this file.
# =============================================================================
verify_cni_artifacts() {
  echo "🔍 Verifying CNI artifacts on the host (up to $(( CNI_ARTIFACT_MAX_WAITS * CNI_ARTIFACT_WAIT ))s)..."
  # Pass the constants into the remote shell as positional args so the
  # single-quoted heredoc body can reference them without local expansion.
  multipass exec "$MASTER_NAME" -- bash -c '
    CNI_BINARY_PATH="$1"
    CNI_CONFIG_PATH="$2"
    MAX_WAITS="$3"
    WAIT="$4"
    for i in $(seq 1 "$MAX_WAITS"); do
      BINARY_OK=0
      CONFIG_OK=0
      [ -f "$CNI_BINARY_PATH" ] && BINARY_OK=1
      [ -f "$CNI_CONFIG_PATH" ] && CONFIG_OK=1
      if [ "$BINARY_OK" -eq 1 ] && [ "$CONFIG_OK" -eq 1 ]; then
        echo "   ✅ CNI artifacts present (attempt $i):"
        echo "      $CNI_BINARY_PATH"
        echo "      $CNI_CONFIG_PATH"
        exit 0
      fi
      # Report which specific file is still missing so the log is actionable
      [ "$BINARY_OK" -eq 0 ] && echo "   attempt $i/$MAX_WAITS — missing: $CNI_BINARY_PATH"
      [ "$CONFIG_OK" -eq 0 ] && echo "   attempt $i/$MAX_WAITS — missing: $CNI_CONFIG_PATH"
      sleep "$WAIT"
    done
    echo "❌ CNI artifacts never appeared after $(( MAX_WAITS * WAIT ))s."
    echo "   Dumping init container logs:"
    kubectl logs -n kube-flannel -l app=flannel \
      -c install-cni-plugin --tail=20 2>/dev/null || true
    kubectl logs -n kube-flannel -l app=flannel \
      -c install-cni        --tail=20 2>/dev/null || true
    exit 1
  ' -- "$CNI_BINARY_PATH" "$CNI_CONFIG_PATH" "$CNI_ARTIFACT_MAX_WAITS" "$CNI_ARTIFACT_WAIT"
}
# =============================================================================
# restart_container_runtime
#   Restarts containerd and kubelet so they pick up the new CNI config.
#   Kubelet can miss the file creation event on first boot if it starts
#   before Flannel's init containers finish writing to the host.
# =============================================================================
restart_container_runtime() {
  echo "🔄 Restarting containerd and kubelet to pick up CNI config..."
  multipass exec "$MASTER_NAME" -- sudo systemctl restart containerd kubelet
}
# =============================================================================
# remove_control_plane_taints
#   Removes the control-plane taint so that CoreDNS (and any other pods) can
#   schedule on the master. Essential for single-node clusters and speeds up
#   a multi-node cluster by letting CoreDNS start before workers join.
# =============================================================================
remove_control_plane_taints() {
  echo "🔓 Removing control-plane taints to allow CoreDNS to schedule..."
  # Both taint keys exist depending on the Kubernetes version — suppress
  # errors for whichever one is absent.
  multipass exec "$MASTER_NAME" -- \
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
  multipass exec "$MASTER_NAME" -- \
    kubectl taint nodes --all node-role.kubernetes.io/master-        2>/dev/null || true
}
# =============================================================================
# wait_for_node_ready
#   Waits up to 10 minutes for the master node to report Ready. Dumps
#   diagnostics on timeout so the failure is immediately actionable.
# =============================================================================
wait_for_node_ready() {
  echo "⏳ Waiting for master node to become Ready (up to 10 minutes)..."
  if ! multipass exec "$MASTER_NAME" -- \
      kubectl wait --for=condition=Ready \
        node/"$MASTER_NAME" \
        --timeout="$NODE_READY_TIMEOUT"; then
    echo "❌ Node never became Ready — dumping diagnostics:"
    multipass exec "$MASTER_NAME" -- kubectl describe node/"$MASTER_NAME"
    multipass exec "$MASTER_NAME" -- sudo journalctl -u kubelet --no-pager -n 50
    exit 1
  fi
}
# =============================================================================
# print_cluster_state
#   Prints the final node and pod state so you can see what you have at a
#   glance without running additional commands manually.
# =============================================================================
print_cluster_state() {
  echo "📋 Final cluster state:"
  multipass exec "$MASTER_NAME" -- kubectl get nodes -o wide
  echo ""
  multipass exec "$MASTER_NAME" -- kubectl get pods -A
}
# =============================================================================
# save_join_command
#   Generates a fresh bootstrap token and saves the full join command to
#   out/join-command.sh on the host so worker init scripts can source it.
# =============================================================================
save_join_command() {
  echo "🔑 Generating worker join command..."
  mkdir -p "$PROJECT_ROOT/out"
  multipass exec "$MASTER_NAME" -- \
    sudo kubeadm token create --print-join-command \
    > "$PROJECT_ROOT/out/join-command.sh"
  chmod +x "$PROJECT_ROOT/out/join-command.sh"
  echo "✅ Join command saved to $PROJECT_ROOT/out/join-command.sh"
}
# =============================================================================
# print_footer
# =============================================================================
print_footer() {
  echo "=================================================="
  echo "✅ Master Initialization Complete!"
  echo "=================================================="
}
run_kubeadm_init() {
  echo "📝 Generating kubeadm configuration..."
  multipass exec "$MASTER_NAME" -- bash -c "cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.15
controlPlaneEndpoint: \"$MASTER_IP:6443\"
networking:
  podSubnet: $POD_CIDR
  serviceSubnet: $SVC_CIDR
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF"
  echo "🚀 Running kubeadm init..."
  multipass exec "$MASTER_NAME" -- sudo kubeadm init \
    --config=/tmp/kubeadm-config.yaml \
    --ignore-preflight-errors=NumCPU,Mem
}
wait_for_cluster_ready() {
  echo "🏁 Entering wait_for_cluster_ready..."
  local KUBECONFIG="--kubeconfig=/home/ubuntu/.kube/config"
  for i in $(seq 1 10); do
    echo "DEBUG: Starting attempt $i..."
    
    # 1. Remove 2>/dev/null so we can see why it's failing
    # 2. Lower timeout to 5s so it returns control to the script faster

    set -x
    if multipass exec "$MASTER_NAME" -- kubectl $KUBECONFIG wait --for=condition=Ready node/"$MASTER_NAME" --timeout=5s; then
      echo "   ✅ Node is Ready."
      return 0
    fi   
    set +x

    echo "   [attempt $i/10] Node not Ready yet, untainting..."
    set -x
    multipass exec "$MASTER_NAME" -- kubectl $KUBECONFIG taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
    multipass exec "$MASTER_NAME" -- kubectl get node "$MASTER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'   
    set +x
    
    echo "DEBUG: Sleeping 10s..."
    sleep 10
  done
  echo "❌ Timeout reached!"
  exit 1
}
setup_network_layer() {
  echo "=================================================="
  echo "🌐 STARTING NETWORK LAYER SETUP"
  echo "=================================================="
  # --- PRE-FLIGHT: FIX PERMISSIONS ---
  # Kubernetes sometimes creates this directory with restrictive ownership.
  # We pre-create it and open it up so Flannel can write its config file.
  echo "📁 Preparing host CNI directory..."
  multipass exec "$MASTER_NAME" -- sudo mkdir -p /etc/cni/net.d
  multipass exec "$MASTER_NAME" -- sudo chmod 777 /etc/cni/net.d

  # --- NEW: STAGE 0 (Wait for Pod to start Pulling/Running) ---
  echo "⏳ Stage 0: Waiting for Flannel Pod to be scheduled..."
  timeout 30s multipass exec "$MASTER_NAME" -- bash -c "until kubectl get pods -n kube-flannel -l app=flannel --no-headers >/dev/null 2>&1; do sleep 2; done"


  # --- STEP 1: APPLY FLANNEL ---
  local APPLY_CMD="kubectl apply -f $FLANNEL_MANIFEST"
  echo "🚀 Running: $APPLY_CMD"
  timeout 20s multipass exec "$MASTER_NAME" -- $APPLY_CMD
  # --- STEP 2: WAIT FOR CNI CONFIG FILE ---

  echo "⏳ Phase 1: Waiting for CNI config file..."
  local j=1
  local TARGET_FILE="/etc/cni/net.d/10-flannel.conflist"
  
  while [ $j -le 20 ]; do
    echo "🔍 [Attempt $j/20] Checking for $TARGET_FILE..."
    
    # We use 'test -f' directly. It returns 0 if exists, 1 if not.
    if multipass exec "$MASTER_NAME" -- sudo test -f "$TARGET_FILE"; then
      echo "   ✅ SUCCESS: $TARGET_FILE detected."
      # Double check by printing the file size to the console
      multipass exec "$MASTER_NAME" -- ls -lh "$TARGET_FILE"
      break
    fi
    echo "   ⚠️ File not found via 'test -f'. Sleeping 5s..."
    sleep 5
    j=$((j + 1))
    
    if [ $j -gt 20 ]; then
      echo "❌ ERROR: CNI config never appeared."
      echo "DEBUG: Current directory content:"
      multipass exec "$MASTER_NAME" -- ls -la /etc/cni/net.d/
      exit 1
    fi
  done

  # --- STEP 3: UNTAINT MASTER (Critical for Single-Node) ---
  echo "🔓 Phase 2: Removing Master taints to allow Pod scheduling..."
  # We use || true because if the taint is already gone, kubectl returns an error.
  # We want to ignore that error and keep going.
  multipass exec "$MASTER_NAME" -- kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
  multipass exec "$MASTER_NAME" -- kubectl taint nodes --all node-role.kubernetes.io/master- || true

  # --- STEP 4: RESTART SERVICES ---
  echo "🔄 Phase 3: Restarting services to pick up new network config..."
  # Removed 'timeout' wrapper to ensure the restart completes fully
  multipass exec "$MASTER_NAME" -- sudo systemctl restart containerd
  multipass exec "$MASTER_NAME" -- sudo systemctl restart kubelet

  # --- STEP 5: WAIT FOR COREDNS ---
  echo "⏳ Phase 4: Waiting for CoreDNS pods to reach READY status..."
  local k=1
  while [ $k -le 24 ]; do
    local DNS_CMD="kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers"
    echo "🔍 [Attempt $k/24] Checking CoreDNS: $DNS_CMD"
    local DNS_RESULT
    DNS_RESULT=$(timeout 15s multipass exec "$MASTER_NAME" -- $DNS_CMD 2>/dev/null || echo "PENDING")
    # If the pod shows '1/1' it is Ready
    if echo "$DNS_RESULT" | grep -q "1/1"; then
      echo "   ✅ SUCCESS: CoreDNS is UP and RUNNING."
      break
    fi
    echo "   ⚠️ CoreDNS not ready. Status: ${DNS_RESULT:-'Pending'}"
    sleep 10
    k=$((k + 1))
    if [ $k -gt 24 ]; then
      echo "❌ ERROR: CoreDNS never reached Ready state."
      multipass exec "$MASTER_NAME" -- kubectl get pods -A
      exit 1
    fi
  done
  echo "=================================================="
  echo "✅ NETWORK LAYER & SCHEDULING FULLY OPERATIONAL"
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
main() {
  parse_args "$@"
  check_idempotency
  reset_previous_state
  disable_swap
  pull_control_plane_images
  run_kubeadm_init
  configure_kubectl_in_vm
  setup_network_layer
  wait_for_cluster_ready
  save_join_command
}
main "$@"
