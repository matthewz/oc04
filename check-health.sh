#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' 
echo -e "${BOLD}=== 🏥 K8s Health Check: $(date +%H:%M:%S) ===${NC}"
# 1. API Server Health
echo -e "\n${BOLD}🧠 Control Plane Health:${NC}"
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ API Server is responding and ready${NC}"
else
    echo -e "  ${RED}❌ API Server is NOT ready!${NC}"
fi
# 2. Node Status Summary (Fixed Quoting)
echo -e "\n${BOLD}💻 Node Status:${NC}"
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' | sed 's/True/Ready/g' | sed 's/False/NotReady/g'
# 3. Resource Pressure
echo -e "\n${BOLD}📊 Resource Usage:${NC}"
kubectl top nodes 2>/dev/null || echo -e "  ${RED}⚠️  Metrics Server not responding${NC}"
# 4. Problem Pods
echo -e "\n${BOLD}🚨 Problem Pods (All Namespaces):${NC}"
# Simplified check: Just show anything not "Running" or "Succeeded"
PROBLEMS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null)
if [ -z "$PROBLEMS" ]; then
    echo -e "  ${GREEN}✅ All pods are healthy.${NC}"
else
    echo -e "${RED}$PROBLEMS${NC}"
fi
# 5. Infrastructure Apps
echo -e "\n${BOLD}🛠️  Infrastructure Apps:${NC}"
# Simplified to avoid the "in (...)" quoting issues in scripts
kubectl get deploy -A | grep -E 'kubernetes-dashboard|metrics-server' || echo "Not found."
echo -e "\n${BOLD}=== Check Complete ===${NC}"
