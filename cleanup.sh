#!/bin/bash
set -euo pipefail
echo "---------------------------------------------------------------"
echo "🛑 Stopping old port-forwards..."
echo "---------------------------------------------------------------"
kill -9 $(lsof -t -i :8001)  2>/dev/null || true
kill -9 $(lsof -t -i :8080)  2>/dev/null || true
kill -9 $(lsof -t -i :8443)  2>/dev/null || true
kill -9 $(lsof -t -i :18789) 2>/dev/null || true
kill -9 $(lsof -t -i :32000) 2>/dev/null || true
echo "---------------------------------------------------------------"
echo "🚀 Starting port-forwards..."
echo "---------------------------------------------------------------"
set -x
###
#kubectl proxy \
#    1> /tmp/kubectl_proxy_out.txt 2>&1 &
###
kubectl port-forward -n longhorn-system \
    svc/longhorn-frontend 8080:80 \
    1> /tmp/longhorn_out.txt 2>&1 &
kubectl port-forward -n kubernetes-dashboard \
    svc/kubernetes-dashboard-kong-proxy 8443:443 \
    1> /tmp/8443.txt 2>&1 &
kubectl port-forward -n oclaw01 \
    svc/oclaw01-service 18789:18789 \
    1> /tmp/oclaw01_out.txt 2>&1 &
kubectl port-forward -n jenkins \
    svc/jenkins-service 32000:8080 \
    1> /tmp/jenkins_out.txt 2>&1 &
set +x
echo "---------------------------------------------------------------"
echo "✅ kubectl proxy: http://localhost:8001"
echo "✅ Longhorn:      http://localhost:8080"
echo "✅ Dashboard:     https://localhost:8443"
echo "✅ oclaw01:       http://localhost:18789"
echo "✅ Jenkins:       http://localhost:32000"
echo "---------------------------------------------------------------"
echo "🔑 Generating Admin Token (valid 24h)..."
echo "---------------------------------------------------------------"
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
echo "---------------------------------------------------------------"
