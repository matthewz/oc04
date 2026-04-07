#!/bin/bash
# =============================================================================
# scripts/ops/clean-longhorn.sh
# Deep cleans Longhorn from a Multipass K8s cluster to allow fresh install.
# =============================================================================
set -euo pipefail
# Source your library
LIB_PATH="$(dirname "$0")/scripts/lib/multipass.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: multipass.sh library not found at $LIB_PATH"
    exit 1
fi
# Configuration
LONGHORN_VERSION="1.10.2"
NAMESPACE="longhorn-system"
MASTER_VM="k8s-master"
# UI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}INFO:${NC} $1"; }
log_warn()  { echo -e "${YELLOW}WARN:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }
# -----------------------------------------------------------------------------
# Additional Wrappers
# -----------------------------------------------------------------------------
# Force remove finalizers from a specific resource type
kube_strip_finalizers() {
    local vm="$1"
    local resource="$2"
    log_info "Stripping finalizers from $resource..."
    
    # Get the names of all resources of this type
    local items
    items=$(kube_exec "$vm" get "$resource" -n "$NAMESPACE" -o name 2>/dev/null || true)
    
    for item in $items; do
        kube_exec "$vm" patch "$item" -n "$NAMESPACE" \
            --type json \
            -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
    done
}
# Check if a namespace exists
namespace_exists() {
    local vm="$1"
    local ns="$2"
    # Use 2>/dev/null to keep the check quiet
    kube_exec "$vm" get namespace "$ns" &>/dev/null
}
# -----------------------------------------------------------------------------
# Cleanup Phases
# -----------------------------------------------------------------------------
phase_pvc_removal() {
    log_info "Phase 1: Removing PVCs and PVs..."
    # We don't want to wait forever if they are stuck
    kube_exec "$MASTER_VM" delete pvc --all --all-namespaces --timeout=30s 2>/dev/null || log_warn "PVCs did not delete cleanly; forcing..."
    kube_exec "$MASTER_VM" delete pv --all --timeout=30s 2>/dev/null || log_warn "PVs did not delete cleanly; forcing..."
}
phase_finalizer_scrub() {
    log_info "Phase 2: Scrubbing stuck Longhorn CRD finalizers..."
    local crds=(
        "volumes.longhorn.io"
        "engines.longhorn.io"
        "replicas.longhorn.io"
        "backups.longhorn.io"
        "sharemanagers.longhorn.io"
    )
    for crd in "${crds[@]}"; do
        kube_strip_finalizers "$MASTER_VM" "$crd"
    done
}
phase_uninstall_logic() {
    log_info "Phase 3: Triggering Uninstaller..."
    
    # 1. Set the deinstalling flag
    kube_exec "$MASTER_VM" patch settings.longhorn.io deinstalling-indicator \
        -n "$NAMESPACE" -p '{"value":"true"}' --type=merge 2>/dev/null || log_warn "Setting deinstalling flag failed (may already be gone)."
    
    # 2. Try Helm first
    if helm status longhorn -n "$NAMESPACE" &>/dev/null; then
        log_info "Helm release found. Uninstalling..."
        helm uninstall longhorn -n "$NAMESPACE" --wait || log_error "Helm uninstall failed."
    else
        log_warn "No Helm release found. Skipping helm uninstall."
    fi
}
phase_disk_wipe() {
    log_info "Phase 4: Physical disk wipe on all nodes..."
    local nodes
    nodes=$(multipass list --format csv | tail -n +2 | cut -d',' -f1)
    
    for node in $nodes; do
        log_info "Scrubbing /var/lib/longhorn on node: $node"
        # Using your vm_exec wrapper to delete the directory
        if vm_exec "$node" "sudo rm -rf /var/lib/longhorn/"; then
            log_info "Successfully wiped $node"
        else
            log_error "Failed to wipe $node"
            return 1
        fi
    done
}
# -----------------------------------------------------------------------------
# force_delete_namespace <vm_name> <namespace>
# Uses the internal API to strip finalizers from a stuck namespace
# FIX: Switched to single quotes for Python -c to prevent Bash $ expansion
# -----------------------------------------------------------------------------
force_delete_namespace() {
    local vm="$1"
    local ns="$2"
    log_warn "Force-clearing namespace finalizers for: $ns"
    
    local ns_json
    ns_json=$(kube_exec "$vm" get namespace "$ns" -o json 2>/dev/null || echo "")
    
    # If the JSON is empty, the namespace is already gone
    [[ -z "$ns_json" ]] && return 0
    
    # FIX: Use single quotes for the python block so Bash doesn't try to parse $
    local cleaned_json
    cleaned_json=$(echo "$ns_json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    if "spec" in data:
        data["spec"]["finalizers"] = []
    if "metadata" in data and "finalizers" in data["metadata"]:
        data["metadata"]["finalizers"] = []
    print(json.dumps(data))
except Exception:
    sys.exit(1)
')
    # Send the raw request to the cluster API
    kube_exec "$vm" replace --raw "/api/v1/namespaces/$ns/finalize" -f - <<< "$cleaned_json" || true
}
# -----------------------------------------------------------------------------
# Phase 5: Namespace Delete
# FIX: Handle the timeout and ensure arguments are passed correctly
# -----------------------------------------------------------------------------
phase_namespace_delete() {
    log_info "Phase 5: Final Namespace Wipe..."
    
    if namespace_exists "$MASTER_VM" "$NAMESPACE"; then
        log_info "Attempting graceful deletion of $NAMESPACE..."
        
        # We catch the failure of the graceful delete to trigger the force delete
        if ! kube_exec "$MASTER_VM" delete namespace "$NAMESPACE" --wait=true --timeout=20s 2>/dev/null; then
            log_warn "Namespace $NAMESPACE is stuck. Initializing hard delete..."
            force_delete_namespace "$MASTER_VM" "$NAMESPACE"
        fi
    else
        log_info "Namespace $NAMESPACE already gone."
    fi
}
# -----------------------------------------------------------------------------
# Main Execution Path
# -----------------------------------------------------------------------------
main() {
    log_info "Starting Deep Clean for Longhorn v$LONGHORN_VERSION"
    
    # Step 1: PVCs
    phase_pvc_removal
    
    # Step 2: Finalizers (CRDs)
    phase_finalizer_scrub
    
    # Step 3: Deployment/Helm
    phase_uninstall_logic
    
    # Step 4: Physical Disk
    if ! phase_disk_wipe; then
        log_error "Disk wipe failed. Cluster might be in an inconsistent state."
        exit 1
    fi
    
    # Step 5: Namespace
    phase_namespace_delete
    
    # Final check - ensure it really is gone before exiting
    if namespace_exists "$MASTER_VM" "$NAMESPACE"; then
       force_delete_namespace "${MASTER_VM}" "${NAMESPACE}" 
    fi
    log_info "====================================================="
    log_info "CLEANUP COMPLETE. Cluster is ready for fresh install."
    log_info "====================================================="
}
# Pass script arguments to main
main "$@"
