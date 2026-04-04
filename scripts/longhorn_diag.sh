

#!/bin/bash
VOL="pvc-cd65aecd-3177-4139-9822-b71c7a4fcace"
NS="longhorn-system"
echo "=== Volume Status ==="
kubectl get volume $VOL -n $NS
echo "=== Engine Status ==="
kubectl get engines -n $NS | grep $VOL
echo "=== Replica Status ==="
kubectl get replicas -n $NS | grep $VOL
echo "=== Longhorn Pods ==="
kubectl get pods -n $NS
