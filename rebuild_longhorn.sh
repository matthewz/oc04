#!/bin/bash
# Set KUBECONFIG to your new Multipass config path
export KUBECONFIG=~/.kube/config-k8s-multipass
echo "🛑 Phase 1: Deep Cleaning Old Longhorn..."
echo "1. Clear the reservations (PVCs/PVs)"
# We use --wait=false so the script doesn't hang on stuck finalizers
kubectl delete pvc --all --all-namespaces --wait=false 2>/dev/null
kubectl delete pv --all --wait=false 2>/dev/null
echo "2. Force-clear the finalizers (Removing the 'Stuck' protection)"
# Targeted removal of finalizers to allow immediate deletion
for res in volumes.longhorn.io engines.longhorn.io replicas.longhorn.io backups.longhorn.io; do
    if kubectl get "$res" -n longhorn-system > /dev/null 2>&1; then
        echo "Removing finalizers for $res..."
        kubectl -n longhorn-system get "$res" -o json | \
        jq '(.items[] | select(.metadata.finalizers != null) | .metadata.finalizers) = []' | \
        kubectl replace --raw "/apis/longhorn.io/v1beta2/namespaces/longhorn-system/$res" -f - 2>/dev/null || true
    fi
done
echo "3. Trigger official uninstaller & Delete software"
kubectl -n longhorn-system patch settings.longhorn.io deinstalling-indicator -p '{"value":"true"}' --type=merge 2>/dev/null || true
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.2/deploy/longhorn.yaml --ignore-not-found
echo "4. Wipe the physical disk storage on Multipass nodes"
# We do this immediately—no need to sleep if finalizers are gone!
for node in k8s-master k8s-worker1 k8s-worker2; do
    echo "🧹 Scrubbing /var/lib/longhorn on $node..."
    multipass exec "$node" -- sudo rm -rf /var/lib/longhorn/
done
echo "5. Final namespace wipe"
kubectl delete namespace longhorn-system --ignore-not-found=true --wait=true
echo "📦 Phase 2: Installing Longhorn v1.6.2..."
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.2/deploy/longhorn.yaml
echo "⏳ Waiting for Longhorn API to wake up..."
# REPLACE 90s sleep with a smart check for the CRD and the Manager Pods
until kubectl get crd settings.longhorn.io >/dev/null 2>&1; do
  echo "Waiting for Longhorn Dictionary (CRDs)..."
  sleep 5
done
echo "⏳ Waiting for Longhorn Manager pods to be Ready..."
kubectl wait --namespace longhorn-system --for=condition=ready pod --selector=app=longhorn-manager --timeout=120s
echo "🚀 Phase 3: Configuring Settings and Backup Jobs..."
# We use 'apply' on individual Settings. 
# Note: In 1.6.x, applying 'Setting' objects via YAML is the most reliable way.
cat <<EOF | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-static
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "1440"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: replica-soft-anti-affinity
  namespace: longhorn-system
spec:
  value: "true"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: storage-over-provisioning-percentage
  namespace: longhorn-system
spec:
  value: "500"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: storage-minimal-available-percentage
  namespace: longhorn-system
spec:
  value: "10"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: default-replica-count
  namespace: longhorn-system
spec:
  value: "1"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
spec:
  value: "nfs://192.168.50.13/nfs/longhorn-backups"
---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-nas-backup
  namespace: longhorn-system
spec:
  name: daily-nas-backup
  groups:
    - default
  task: backup
  cron: "0 2 * * *"
  retain: 7
  concurrency: 1
EOF
echo "✅ Longhorn 1.6.2 is fresh, clean, and configured!"
