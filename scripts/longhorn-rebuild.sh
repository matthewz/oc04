#!/bin/bash
set -euo pipefail
export KUBECONFIG=~/.kube/config-k8s-multipass
GREEN='\033[0;32m'
NC='\033[0m'
LONGHORN_VERSION="1.6.2"

# ── Phase 1: Deep Clean ───────────────────────────────────────────────────────
# This script's ONLY job now: make the cluster safe for helmfile to install into.
# Helmfile owns the install. We own the destruction.
echo "🛑 Phase 1: Deep Cleaning Old Longhorn..."
echo "  1. Clearing PVCs/PVs..."
kubectl delete pvc --all --all-namespaces --wait=false 2>/dev/null || true
kubectl delete pv  --all               --wait=false 2>/dev/null || true

echo "  2. Force-clearing stuck finalizers..."
for res in volumes.longhorn.io engines.longhorn.io replicas.longhorn.io backups.longhorn.io; do
    if kubectl get "$res" -n longhorn-system > /dev/null 2>&1; then
        echo "     Removing finalizers for $res..."
        kubectl -n longhorn-system get "$res" -o json | \
        jq '(.items[] | select(.metadata.finalizers != null) | .metadata.finalizers) = []' | \
        kubectl replace --raw \
            "/apis/longhorn.io/v1beta2/namespaces/longhorn-system/$res" \
            -f - 2>/dev/null || true
    fi
done

echo "  3. Triggering official Longhorn uninstaller..."
kubectl -n longhorn-system patch settings.longhorn.io deinstalling-indicator \
    -p '{"value":"true"}' --type=merge 2>/dev/null || true
# Use Helm to delete if a release exists — otherwise fall back to kubectl
if helm status longhorn -n longhorn-system &>/dev/null; then
    echo "     Helm release found — uninstalling via Helm..."
    helm uninstall longhorn -n longhorn-system --wait
else
    echo "     No Helm release found — falling back to kubectl delete..."
    LOCAL_MANIFEST="./longhorn-${LONGHORN_VERSION}.yaml"
    if [ ! -f "$LOCAL_MANIFEST" ]; then
        echo "     Fetching manifest from GitHub..."
        curl -sSL \
            "https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/longhorn.yaml" \
            -o "$LOCAL_MANIFEST"
    else
        echo "     Using cached local manifest..."
    fi
    kubectl delete -f "$LOCAL_MANIFEST" --ignore-not-found
fi

echo "  4. Wiping physical disk storage on all nodes..."
NODES=$(multipass list --format csv | tail -n +2 | cut -d',' -f1)
echo "     Found nodes: $NODES"
for node in $NODES; do
    echo "     🧹 Scrubbing /var/lib/longhorn on $node..."
    multipass exec "$node" -- sudo rm -rf /var/lib/longhorn/ &
done
wait
echo "✅ Disk wipe complete"

echo "  5. Final namespace wipe..."
kubectl delete namespace longhorn-system --ignore-not-found=true --wait=true
echo -e "${GREEN}✅ Cluster is clean — helmfile is clear to install${NC}"

# Helmfile takes it from here.
