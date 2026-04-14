#!/bin/bash
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' 
echo -e "${BOLD}=== 🏥 FULL STACK HEALTH CHECK: $(date +%H:%M:%S) ===${NC}"
# --- SECTION 1: VIRTUAL MACHINES (MULTIPASS) ---
echo -e "\n${BOLD}🖥️  Multipass Infrastructure:${NC}"
if command -v multipass &> /dev/null; then
    multipass list --format table | sed 's/^/  /'
    read -a nodes <<< $(multipass list | awk 'NR>1 {print $1}')
    for node in "${nodes[@]}"; do
       multipass exec "$node" -- bash -c \
       "echo -n '   - ' ; hostname ; \
        echo -n '     ' ; df -h / | tail -1 | awk '{print \"Disk: \" \$5}' ; \
        echo -n '     ' ; free -h | grep Mem | awk '{print \"Mem:  \" \$3 \"/\" \$2}'" 2>/dev/null
    done
else
    echo -e "  ${RED}❌ Multipass command not found.${NC}"
fi
# --- SECTION 2: K8S CONTROL PLANE (THE WAIT LOOP) ---
echo -e "\n${BOLD}🧠 Kubernetes Control Plane:${NC}"
MAX_RETRIES=15
COUNT=0
API_READY=false
while [ $COUNT -lt $MAX_RETRIES ]; do
    # Try to hit the API
    if kubectl get --raw='/readyz' >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ API Server is responding and ready${NC}"
        API_READY=true
        break
    else
        # Troubleshooting: Try a simple ping to see if the host even knows where the VM is
        # We extract the IP from the kubeconfig
        KUBE_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        
        echo -e "  ${YELLOW}🕒 [$((COUNT+1))/$MAX_RETRIES] Waiting for API ($KUBE_IP)...${NC}"
        
        # Check if the route exists at all
        if ! ping -c 1 -W 1 "$KUBE_IP" >/dev/null 2>&1; then
            echo -e "     ⚠️  No network route to $KUBE_IP yet."
        fi
        
        sleep 4
        ((COUNT++))
    fi
done
if [ "$API_READY" = false ]; then
    echo -e "  ${RED}❌ API Server is NOT ready! Giving up after $MAX_RETRIES attempts.${NC}"
    # If API is down, the rest of the script will fail, so we exit
    exit 1
fi
# --- SECTION 3: K8S NODES ---
echo -e "\n${BOLD}💻 K8s Node Status:${NC}"
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' | sed 's/True/Ready/g' | sed 's/False/NotReady/g' | sed 's/^/  /'
# --- SECTION 4: K8S PODS ---
echo -e "\n${BOLD}🚨 Problem Pods (All Namespaces):${NC}"
PROBLEMS=$(kubectl get pods -A --no-headers 2>/dev/null | awk '
{
    # Split the READY column (e.g. "2/3") into ready and total
    split($3, ready, "/")
    
    not_ready   = (ready[1] != ready[2])
    bad_status  = ($4 ~ /Completed|CrashLoopBackOff|Error|OOMKilled|ImagePullBackOff|ErrImagePull|Terminating|Pending|Unknown/)
    high_restart = ($5+0 > 3)
    
    if (not_ready || bad_status || high_restart) print
}')
if [ -z "$PROBLEMS" ]; then
    echo -e "  ${GREEN}✅ No unhealthy pods were found.${NC}"
else
    echo -e "  ${RED}${PROBLEMS}${NC}"
fi
CMD="kubectl get pods -A --no-headers | grep longhorn"
#echo "CMD=_${CMD}_" ; eval $CMD
# --- SECTION 5: METRICS ---
echo -e "\n${BOLD}📊 K8s Resource Usage:${NC}"
kubectl top nodes 2>/dev/null | sed 's/^/  /' || echo -e "  ${RED}⚠️  Metrics Server not responding${NC}"
echo -e "\n${BOLD}=== Check Complete ===${NC}"
