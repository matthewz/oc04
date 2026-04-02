#!/bin/bash
set -e # Exit on error
echo "Stopping old port-forwards..."
# Kill processes using the ports
kill $(lsof -t -i:8443) 2>/dev/null || true
kill $(lsof -t -i:8080) 2>/dev/null || true
echo "Starting new tunnel to Bitnami Dashboard..."
# Bitnami service is named 'kubernetes-dashboard' by default
# We map local 8443 to the container's 443 (HTTPS)
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 > /dev/null 2>&1 &
echo "Starting new tunnel to Longhorn..."
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 > /dev/null 2>&1 &
echo "---------------------------------------------------------------"
echo "✅ Dashboard: https://localhost:8443"
echo "✅ Longhorn:  http://localhost:8080"
echo "---------------------------------------------------------------"
echo "🔑 Generating Admin Token..."
# Using Bitnami's default admin service account name
kubectl -n kubernetes-dashboard create token kubernetes-dashboard-admin --duration=24h
echo "---------------------------------------------------------------"
