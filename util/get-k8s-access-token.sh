#!/bin/bash

echo "🚀 Get the admin-user-secret ... "
set -x
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
set +x 
echo ""
