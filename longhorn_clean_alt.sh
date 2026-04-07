#!/bin/bash
set -euo pipefail
# ... [Keep your Config/Logging Helpers/NC/Colors as they are] ...
# -----------------------------------------------------------------------------
# Robust Execution Helper
# -----------------------------------------------------------------------------
# Wraps kube_exec to handle cases where resources are already gone
safe_kube_delete() {
    local vm="$1"
    shift
    # We allow this to fail (|| true) to maintain idempotency
    kube_exec "$vm" delete "$@" --ignore-not-found=true --wait=false 2>/dev/null || true
}
# -----------------------------------------------------------------------------
# Improved force_delete_namespace (The Python Fix)
# -----------------------------------------------------------------------------
force_delete_namespace() {
    local vm="$1"
    local ns="$2"
    log_warn "Force-clearing namespace finalizers for: $ns"
    
    local ns_json
    ns_json=$(kube_exec "$vm" get namespace "$ns" -o json 2>/dev/null || echo "")
    
    [[ -z "$ns_json" ]] && return 0
    # CORRECTED: Single quotes around the python script
    local cleaned_json
    cleaned_json=$(echo "$ns_json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    data.setdefault("spec", {})["finalizers"] = []
    if "metadata" in data and "finalizers" in data["metadata"]:
        data["metadata"]["finalizers"] = []
    print(json.dumps(data))
except Exception:
    sys.exit(1)
')
    
    kube_exec "$vm" replace --raw "/api/v1/namespaces/$ns/finalize" -f - <<< "$cleaned_json" || true
}
# -----------------------------------------------------------------------------
# Phase 4: Enhanced Disk Wipe (The Mount-Aware Wipe)
# -----------------------------------------------------------------------------
phase_disk_wipe() {
    log_info "Phase 4: Physical disk wipe and unmounting..."
    # Only target VMs starting with "k8s-"
    local nodes
    nodes=$(multipass list --format csv | tail -n +2 | cut -d',' -f1 | grep "^k8s-" || echo "")
    
    for node in $nodes; do
        log_info "Cleaning node: $node"
        
        # 1. Unmount any lingering Longhorn volumes to prevent "Device or resource busy"
        vm_exec "$node" "sudo shell -c 'mount | grep longhorn | cut -d\" \" -f3 | xargs -r umount -l'" || true
        
        # 2. Kill any processes using the directory (like orphan longhorn-engine processes)
        vm_exec "$node" "sudo fuser -k /var/lib/longhorn/ 2>/dev/null" || true
        
        # 3. Actual Wipe
        if vm_exec "$node" "sudo rm -rf /var/lib/longhorn/"; then
            log_info "  Successfully wiped /var/lib/longhorn on $node"
        else
            log_error "  Failed to wipe $node"
        fi
    done
}
# -----------------------------------------------------------------------------
# New Phase 6: Global CRD Removal
# -----------------------------------------------------------------------------
phase_crd_cleanup() {
    log_info "Phase 6: Removing Longhorn CRD definitions..."
    local crds
    crds=$(kube_exec "$MASTER_VM" get crd -o name | grep longhorn.io || echo "")
    
    for crd in $crds; do
        # Strip finalizers from the CRD definition itself!
        kube_exec "$MASTER_VM" patch "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kube_exec "$MASTER_VM" delete "$crd" --ignore-not-found=true --timeout=5s 2>/dev/null || true
    done
}
# -----------------------------------------------------------------------------
# Main Execution Path
# -----------------------------------------------------------------------------
main() {
    log_info "Starting Deep Clean for Longhorn v$LONGHORN_VERSION"
    # 1. PV/PVCs (Using the safe wrapper)
    log_info "Phase 1: Removing Storage Resources..."
    safe_kube_delete "$MASTER_VM" pvc --all --all-namespaces
    safe_kube_delete "$MASTER_VM" pv --all
    # 2. CRD Instances Finalizers
    phase_finalizer_scrub
    # 3. Logic & Helm
    phase_uninstall_logic
    # 4. Host Cleanup (The most common cause of "reinstall" failures)
    phase_disk_wipe
    # 5. Namespace (The "Assassination" phase)
    phase_namespace_delete
    # 6. Global CRDs (Optional but recommended for fresh starts)
    phase_crd_cleanup
    log_info "====================================================="
    log_info "CLEANUP COMPLETE. Cluster is ready for fresh install."
    log_info "====================================================="
}
main "$@"
