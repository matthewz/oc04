#!/bin/bash

echo "=== Kubernetes Cluster Health Check ==="
echo ""
echo "📊 Cluster Info:"
kubectl cluster-info
echo ""
echo "📊 Nodes:"
kubectl get nodes -o wide
echo ""
echo "🔧 System Pods:"
kubectl get pods -n kube-system
echo ""
echo "📦 All Namespaces Pod Status:"
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
echo ""
echo "💾 Component statuses:"
kubectl get componentstatuses
kubectl get --raw='/readyz?verbose'
echo ""
echo "💾 Resource Usage:"
kubectl top nodes 2>/dev/null || echo "Metrics server not installed"
echo ""
echo "⚠️  Events (last 10 warnings/errors):"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -E 'Warning|Error' | tail -10
echo ""
echo "📊 Check Dashboard:"
kubectl get pods -n kubernetes-dashboard
echo ""
echo "📊 Check if metrics server is running:"
kubectl top nodes
kubectl top pods -A
echo ""
