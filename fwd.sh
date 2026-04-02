#!/bin/bash

        echo "Stopping old port-forwards..."
        kill $(lsof -t -i:8443) 2>/dev/null || true
        kill -9 $(lsof -t -i :8080) 2> /dev/null || true
        echo "Starting new tunnel to Dashboard..."
        kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard-kong-proxy 8443:80 > /dev/null 2>&1 &
        echo "Getting the Dashboard token..."
        kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
        echo "Starting new tunnel to longhorn..."
        echo "✅ Dashboard is now live at http://localhost:8443"
        kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 > /dev/null 2>&1 & 
        echo "✅ Longhorn is now live at http://localhost:8080"

exit 0
