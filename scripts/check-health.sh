
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
    multipass list --format table \
    | sed 's/^/  /'
    read -a nodes <<< $(
    multipass list \
    | grep Running \
    | awk 'NR>1 {print $1}'
    )
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
    if kubectl get --raw='/readyz' >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ API Server is responding and ready${NC}"
        API_READY=true
        break
    else
        KUBE_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        echo -e "  ${YELLOW}🕒 [$((COUNT+1))/$MAX_RETRIES] Waiting for API ($KUBE_IP)...${NC}"
        if ! ping -c 1 -W 1 "$KUBE_IP" >/dev/null 2>&1; then
            echo -e "     ⚠️  No network route to $KUBE_IP yet."
        fi
        sleep 4
        ((COUNT++))
    fi
done
if [ "$API_READY" = false ]; then
    echo -e "  ${RED}❌ API Server is NOT ready! Giving up after $MAX_RETRIES attempts.${NC}"
    exit 1
fi
# --- SECTION 3: K8S NODES ---
echo -e "\n${BOLD}💻 K8s Node Status:${NC}"
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' \
    | sed 's/True/Ready/g' \
    | sed 's/False/NotReady/g' \
    | sed 's/^/  /'
# --- SECTION 3.5: ENDPOINTS ---
# Strategy:
#   - Pull all endpoints across every namespace with -o json
#   - Use 'jq' to flatten them into "NAMESPACE SERVICE IP PORT" lines
#   - Skip the <none> / headless entries (no IP assigned yet)
#   - For each IP:PORT, do a 2-second TCP connect test via curl
#     curl --connect-timeout is the cleanest cross-platform option;
#     nc -zw2 is a good fallback if curl isn't available
echo -e "\n${BOLD}🔌 Endpoints & Connectivity Tests:${NC}"
# We use --no-headers + custom columns for a quick human-readable summary first
echo -e "  ${BOLD}--- Endpoint Listing ---${NC}"
kubectl get endpoints -A --no-headers 2>/dev/null \
    | awk '{printf "  %-20s %-40s %s\n", $1, $2, $3}' \
    | sed 's/^/  /'
# Now the actual testing loop
echo -e "\n  ${BOLD}--- Connectivity Tests (TCP) ---${NC}"
# jq extracts a clean stream of: NAMESPACE SERVICE IP PORT
# We skip entries where .subsets is null (no ready pods behind the service)
kubectl get endpoints -A -o json 2>/dev/null | jq -r '
  .items[] |
  . as $ep |
  # Guard: skip endpoints with no subsets at all
  select(.subsets != null) |
  .subsets[] |
  . as $sub |
  # Guard: skip subsets with no addresses (all pods unready)
  select(.addresses != null) |
  .addresses[].ip as $ip |
  .ports[]? |
  # Emit one line per IP+port combination
  [$ep.metadata.namespace, $ep.metadata.name, $ip, (.port | tostring)] |
  join(" ")
' | while read -r NAMESPACE SVC_NAME IP PORT; do
    # Skip the kubernetes API endpoint itself — we already checked it above
    # and curl-testing 443 from inside a node can be noisy
    if [[ "$SVC_NAME" == "kubernetes" && "$NAMESPACE" == "default" ]]; then
        echo -e "    ${YELLOW}⏭️  Skipping internal API endpoint: $SVC_NAME ($IP:$PORT)${NC}"
        continue
    fi
    LABEL="${NAMESPACE}/${SVC_NAME} → ${IP}:${PORT}"
    # --- TCP connectivity test ---
    # curl's --connect-timeout attempts a TCP handshake only; the 'telnet://'
    # scheme means it dials the port but sends nothing — safe for any protocol.
    # Exit code 0  = connected (TCP handshake succeeded)
    # Exit code 7  = connection refused
    # Exit code 28 = timed out
    if curl -s --connect-timeout 2 "telnet://${IP}:${PORT}" >/dev/null 2>&1; then
        echo -e "    ${GREEN}✅ OPEN   ${LABEL}${NC}"
    else
        EXIT_CODE=$?
        case $EXIT_CODE in
            7)  STATUS="REFUSED " ; COLOR=$RED    ;;
            28) STATUS="TIMEOUT " ; COLOR=$YELLOW ;;
            *)  STATUS="ERROR($EXIT_CODE)" ; COLOR=$RED ;;
        esac
        echo -e "    ${COLOR}❌ ${STATUS} ${LABEL}${NC}"
    fi
done
# --- SECTION 4: K8S PODS ---
echo -e "\n${BOLD}🚨 Problem Pods (All Namespaces):${NC}"
PROBLEMS=$(kubectl get pods -A --no-headers 2>/dev/null | awk '
{
    split($3, ready, "/")
    not_ready    = (ready[1] != ready[2])
    bad_status   = ($4 ~ /Completed|CrashLoopBackOff|Error|OOMKilled|ImagePullBackOff|ErrImagePull|Terminating|Pending|Unknown/)
    high_restart = ($5+0 > 3)
    if (not_ready || bad_status || high_restart) print
}')
if [ -z "$PROBLEMS" ]; then
    echo -e "  ${GREEN}✅ No unhealthy pods were found.${NC}"
else
    echo -e "  ${RED}${PROBLEMS}${NC}"
fi
# --- SECTION 5: METRICS ---
echo -e "\n${BOLD}📊 K8s Resource Usage:${NC}"
kubectl top nodes 2>/dev/null | sed 's/^/  /' || echo -e "  ${RED}⚠️  Metrics Server not responding${NC}"
echo -e "\n${BOLD}=== Check Complete ===${NC}"
