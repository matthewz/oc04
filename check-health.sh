#!/bin/bash
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' 
echo -e "${BOLD}=== 🏥 FULL STACK HEALTH CHECK: $(date +%H:%M:%S) ===${NC}"
# --- SECTION 1: VIRTUAL MACHINES (MULTIPASS) ---
echo -e "\n${BOLD}🖥️  Multipass Infrastructure:${NC}"
if command -v multipass &> /dev/null; then
    # List VMs and their IP/State
    multipass list --format table | sed 's/^/  /'
    
    # Check Disk/Memory of all RUNNING instances
    echo -e "\n${BOLD}💾 Node Resource Health (Internal):${NC}"
    multipass exec --all -- bash -c "echo -n '  - '; hostname; echo -n '    '; df -h / | tail -1 | awk '{print \"Disk: \" \$5}'; echo -n '    '; free -h | grep Mem | awk '{print \"Mem:  \" \$3 \"/\" \$2}'" 2>/dev/null
else
    echo -e "  ${RED}❌ Multipass command not found.${NC}"
fi
# --- SECTION 2: K8S CONTROL PLANE ---
echo -e "\n${BOLD}🧠 Kubernetes Control Plane:${NC}"
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ API Server is responding and ready${NC}"
else
    echo -e "  ${RED}❌ API Server is NOT ready!${NC}"
fi
# --- SECTION 3: K8S NODES ---
echo -e "\n${BOLD}💻 K8s Node Status:${NC}"
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' | sed 's/True/Ready/g' | sed 's/False/NotReady/g' | sed 's/^/  /'
# --- SECTION 4: K8S PODS ---
echo -e "\n${BOLD}🚨 Problem Pods (All Namespaces):${NC}"
PROBLEMS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null)
if [ -z "$PROBLEMS" ]; then
    echo -e "  ${GREEN}✅ No unhealthy pods were found.${NC}"
else
    echo -e "${RED}$PROBLEMS${NC}"
fi
# --- SECTION 5: METRICS ---
echo -e "\n${BOLD}📊 K8s Resource Usage:${NC}"
kubectl top nodes 2>/dev/null | sed 's/^/  /' || echo -e "  ${RED}⚠️  Metrics Server not responding${NC}"
echo -e "\n${BOLD}=== Check Complete ===${NC}"
