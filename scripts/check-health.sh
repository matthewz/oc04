#!/bin/bash
# =============================================================================
# FULL STACK HEALTH CHECK
# =============================================================================
# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'
# =============================================================================
# VIRTUAL MACHINES (MULTIPASS)
# =============================================================================
check_multipass() {
    echo -e "\n${BOLD}🖥️  Multipass Infrastructure:${NC}"
    if ! command -v multipass &> /dev/null; then
        echo -e "  ${RED}❌ Multipass command not found.${NC}"
        return 1
    fi
    # Print header
    printf "  %-20s %-10s %-16s %-20s %-10s %-12s %-6s\n" \
        "Name" "State" "IPv4" "Image" "CPU%" "Memory" "Disk"
    printf "  %s\n" "$(printf '%.0s-' {1..90})"
    # FIX: Use grep to only pick lines that start with a VM name (alphanumeric)
    # This avoids the script getting confused by the extra IP address lines.
    while IFS= read -r line; do
        local name state ipv4 image cpu mem disk
        
        name=$(echo  "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        ipv4=$(echo  "$line" | awk '{print $3}')
        image=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs)
        
        cpu="N/A"
        mem="N/A"
        disk="N/A"
        if [[ "$state" == "Running" ]]; then
            # FIX: Added '< /dev/null' so multipass doesn't consume the 'while' loop input
            read -r cpu mem disk <<< "$(
                multipass exec "$name" < /dev/null -- bash -c \
                    "cpu=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' \
                           | cut -d'%' -f1 | tr -d ' ') ; \
                     mem=\$(free -h | grep Mem | awk '{print \$3\"/\"\$2}') ; \
                     disk=\$(df -h / | tail -1 | awk '{print \$5}') ; \
                     echo \"\$cpu \$mem \$disk\"" 2>/dev/null
            )"
        fi
        printf "  %-20s %-10s %-16s %-20s %-10s %-12s %-6s\n" \
            "$name" "$state" "$ipv4" "$image" "${cpu}%" "$mem" "$disk"
    done < <(multipass list | grep -E '^[a-zA-Z0-9]')
}
# =============================================================================
# K8S CONTROL PLANE (API READINESS WAIT LOOP)
# =============================================================================
check_api_server() {
    echo -e "\n${BOLD}🧠 Kubernetes Control Plane:${NC}"
    local max_retries=15
    local count=0
    local api_ready=false
    local kube_ip
    while [ $count -lt $max_retries ]; do
        if kubectl get --raw='/readyz' >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ API Server is responding and ready${NC}"
            api_ready=true
            break
        else
            kube_ip=$(kubectl config view --minify \
                        -o jsonpath='{.clusters[0].cluster.server}' \
                      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
            echo -e "  ${YELLOW}🕒 [$((count+1))/$max_retries] Waiting for API ($kube_ip)...${NC}"
            if ! ping -c 1 -W 1 "$kube_ip" >/dev/null 2>&1; then
                echo -e "     ⚠️  No network route to $kube_ip yet."
            fi
            sleep 4
            ((count++))
        fi
    done
    if [ "$api_ready" = false ]; then
        echo -e "  ${RED}❌ API Server is NOT ready! Giving up after $max_retries attempts.${NC}"
        return 1   # Caller decides whether to exit
    fi
}
# =============================================================================
# PROBLEM PODS
# =============================================================================
check_pods() {
    echo -e "\n${BOLD}🚨 Problem Pods (All Namespaces):${NC}"
    local problems
    problems=$(kubectl get pods -A --no-headers 2>/dev/null | awk '
    {
        split($3, ready, "/")
        not_ready    = (ready[1] != ready[2])
        bad_status   = ($4 ~ /Completed|CrashLoopBackOff|Error|OOMKilled|ImagePullBackOff|ErrImagePull|Terminating|Pending|Unknown/)
        high_restart = ($5+0 > 3)
        if (not_ready || bad_status || high_restart) print
    }')
    if [ -z "$problems" ]; then
        echo -e "  ${GREEN}✅ No unhealthy pods were found.${NC}"
    else
        echo -e "  ${RED}${problems}${NC}"
    fi
}
# =============================================================================
# ENDPOINTS & CONNECTIVITY TESTS
# =============================================================================
check_endpoints() {
    echo -e "\n${BOLD}🔌 Service Routing & Endpoints:${NC}"
    
    # --- Human-readable listing ---
    printf "  ${BOLD}%-20s %-45s %-15s %s${NC}\n" "NAMESPACE" "SERVICE" "CLUSTER-IP" "POD ENDPOINTS"
    printf "  %s\n" "$(printf '%.0s-' {1..115})"
    local svc_data ep_data
    svc_data=$(kubectl get svc -A -o json 2>/dev/null)
    ep_data=$(kubectl get endpoints -A -o json 2>/dev/null)
    # Use JQ to map Services to Endpoints, and extract IP:Port + Pod Name
    echo "$svc_data" | jq -r --argjson eps "$ep_data" '
      .items[] | . as $svc |
      ($eps.items[] | select(.metadata.name == $svc.metadata.name and .metadata.namespace == $svc.metadata.namespace)) as $ep |
      
      # Create a list of IP:Port strings
      [
        $ep.subsets[]? | . as $sub | 
        ($sub.addresses[]?.ip + ":" + ($sub.ports[]?.port | tostring))
      ] | unique | join(",") as $pod_ips |
      # Create a list of unique Pod Names from targetRefs
      [
        $ep.subsets[]? | .addresses[]? | .targetRef | select(.kind == "Pod") | .name
      ] | unique | join(", ") as $pod_names |
      "\($svc.metadata.namespace)|\($svc.metadata.name)|\($svc.spec.clusterIP)|\($pod_ips)|\($pod_names)"
    ' | while IFS='|' read -r ns name cluster_ip ips pods; do
        # Print the main Service line
        printf "  %-20s %-45s %-15s %s\n" "$ns" "$name" "$cluster_ip" "${ips:-<none>}"
        
        # Print the Pod names on an indented line if they exist
        if [[ -n "$pods" ]]; then
            # Using \033[2m for "dim" text to keep it readable but distinct
            echo -e "    \033[2m└─ Pods: $pods${NC}"
        fi
    done
    # --- TCP connectivity tests ---
    echo -e "\n  ${BOLD}--- Connectivity Tests (TCP to Pods) ---${NC}"
    echo "$ep_data" | jq -r '
      .items[] | . as $ep | select(.subsets != null) | .subsets[] | . as $sub |
      select(.addresses != null) | .addresses[] | . as $addr |
      $sub.ports[]? |
      [$ep.metadata.namespace, $ep.metadata.name, $addr.ip, (.port | tostring), ($addr.targetRef.name // "unknown")] | join(" ")
    ' | while read -r namespace svc_name ip port pod_name; do
        if [[ "$svc_name" == "kubernetes" && "$namespace" == "default" ]]; then
            continue
        fi
        
        local label="${namespace}/${svc_name} (${pod_name}) → ${ip}:${port}"
        if curl -s --connect-timeout 2 "telnet://${ip}:${port}" >/dev/null 2>&1; then
            echo -e "    ${GREEN}✅ OPEN    ${label}${NC}"
        else
            echo -e "    ${RED}❌ FAIL    ${label}${NC}"
        fi
    done
}
check_storage() {
    echo -e "\n💾 Storage & Persistence Status (PVC -> PV):"
    echo "  NAMESPACE / PVC NAME                PV NAME                                    CAPACITY  AGE"
    echo "  ----------------------------------------------------------------------------------------------"
    # Get PVC info across all namespaces
    # Columns: $1=NS, $2=Name, $4=Status, $5=PV_Name, $6=Capacity, $7=AccessMode, $8=StorageClass, $9=Age
    STORAGE_DATA=$(kubectl get pvc -A --no-headers 2>/dev/null)
    if [ -z "$STORAGE_DATA" ]; then
        echo "  (No PersistentVolumeClaims found in cluster)"
    else
        echo "$STORAGE_DATA" | awk '{
            # Main Line: Namespace/PVC Name | PV Name | Capacity | Age
            printf "  %-35s %-42s %-9s %-5s\n", $1"/"$2, $5, $6, $9;
            
            # Indented Line: Status, StorageClass, and Access Mode
            # Using └─ to show the "physical" backing of the virtual claim
            printf "    └─ STATUS: %s | CLASS: %s | ACCESS: %s\n", $4, $8, $7;
        }'
    fi
    # Check for "Lost" or "Failed" Physical Volumes (PVs)
    # Ignores Bound (Used) and Available (Ready for use)
    ERRORS=$(kubectl get pv --no-headers 2>/dev/null | grep -ivE "Bound|Available")
    if [ ! -z "$ERRORS" ]; then
        echo -e "\n  ⚠️  WARNING: Unhealthy Physical Volumes (PV) Detected:"
        echo "$ERRORS" | awk '{printf "  %-40s %s\n", $1, $5}'
    fi
}
# =============================================================================
# K8S NODE HEALTH & RESOURCE USAGE
# =============================================================================
check_nodes() {
    echo -e "\n${BOLD}💻 Node Status & Resource Usage:${NC}"
    
    # Header
    printf "  ${BOLD}%-15s %-10s %-12s %-8s %-15s %-10s${NC}\n" \
        "NODE NAME" "STATUS" "CPU(cores)" "CPU(%)" "MEMORY(bytes)" "MEMORY(%)"
    printf "  %s\n" "$(printf '%.0s-' {1..80})"
    # Fetch status and metrics
    local nodes_status metrics
    nodes_status=$(kubectl get nodes -o json 2>/dev/null)
    metrics=$(kubectl top nodes --no-headers 2>/dev/null)
    # Process each node found in the status JSON
    echo "$nodes_status" | jq -r '.items[] | .metadata.name' | while read -r node; do
        # Get status
        local status
        status=$(echo "$nodes_status" | jq -r ".items[] | select(.metadata.name==\"$node\") | .status.conditions[] | select(.type==\"Ready\") | .status")
        [[ "$status" == "True" ]] && status="${GREEN}Ready${NC}" || status="${RED}NotReady${NC}"
        # Extract metrics for this specific node from the 'top' output
        local cpu_c cpu_p mem_b mem_p
        if [[ -n "$metrics" ]]; then
            read -r _ cpu_c cpu_p mem_b mem_p <<< "$(echo "$metrics" | grep "^$node ")"
        else
            cpu_c="N/A"; cpu_p="N/A"; mem_b="N/A"; mem_p="N/A"
        fi
        printf "  %-15s %-20b %-12s %-8s %-15s %-10s\n" \
            "$node" "$status" "$cpu_c" "$cpu_p" "$mem_b" "$mem_p"
    done
}
check_ingress() {
    echo -e "\n🌐 Cluster-Wide Ingress Status (Entry Points):"
    echo "  NAMESPACE/NAME                      HOSTS                          ADDRESS          AGE"
    echo "  ---------------------------------------------------------------------------------------"
    # Get list of Namespaces and Names
    INGRESS_LIST=$(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1"/"$2}')
    if [ -z "$INGRESS_LIST" ]; then
        echo "  (No Ingress resources found in cluster)"
    else
        for item in $INGRESS_LIST; do
            NS=$(echo $item | cut -d'/' -f1)
            NAME=$(echo $item | cut -d'/' -f2)
            # 1. Get Hosts (handle empty/wildcard)
            HOSTS=$(kubectl get ingress "$NAME" -n "$NS" -o jsonpath='{.spec.rules[*].host}' 2>/dev/null)
            [ -z "$HOSTS" ] && HOSTS="*"
            # 2. Get Address
            ADDR=$(kubectl get ingress "$NAME" -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[*].ip}{.status.loadBalancer.ingress[*].hostname}' 2>/dev/null)
            [ -z "$ADDR" ] && ADDR="<PENDING>"
            # 3. Get Age
            AGE=$(kubectl get ingress "$NAME" -n "$NS" --no-headers | awk '{print $NF}')
            # 4. IMPROVED SERVICE LOOKUP (The Fix)
            # This version looks at ALL possible places a service name can hide in the YAML
            SVC=$(kubectl get ingress "$NAME" -n "$NS" -o jsonpath='{..backend.service.name}{..backend.serviceName}' 2>/dev/null)
            
            # 5. Get Port (Optional but helpful)
            PORT=$(kubectl get ingress "$NAME" -n "$NS" -o jsonpath='{..backend.service.port.number}{..backend.servicePort}' 2>/dev/null)
            # Print Row 1
            printf "  %-35s %-30s %-16s %-10s\n" "$NS/$NAME" "$HOSTS" "$ADDR" "$AGE"
            
            # Print Row 2 (Backend Service and Port)
            if [ ! -z "$SVC" ]; then
                printf "    └─ BACKEND: %s:%s\n" "$SVC" "$PORT"
            else
                printf "    └─ BACKEND: (none discovered)\n"
            fi
            
            # Backend Validation
            if [ ! -z "$SVC" ]; then
                if ! kubectl get svc "$SVC" -n "$NS" >/dev/null 2>&1; then
                    VALIDATION_ERRORS+="- Ingress [$NS/$NAME] points to missing Service [$SVC]\n"
                fi
            fi
        done
    fi
    echo -e "\n  🔍 Backend Validation Status:"
    if [ -z "$VALIDATION_ERRORS" ] && [ ! -z "$INGRESS_LIST" ]; then
        echo "  ✅ All backends verified: Ingress -> Service connectivity is valid."
    elif [ ! -z "$VALIDATION_ERRORS" ]; then
        echo -e "  ❌ ERROR: Broken backends found:\n$VALIDATION_ERRORS"
    fi
}
# =============================================================================
# MAIN
# =============================================================================
main() {
    echo -e "${BOLD}=== 🏥 FULL STACK HEALTH CHECK: $(date +%H:%M:%S) ===${NC}"
    check_multipass
    if ! check_api_server; then
        echo -e "\n${RED}Aborting remaining checks: cluster is unreachable.${NC}"
        exit 1
    fi
    check_storage
    check_nodes
    check_ingress
    check_endpoints
    check_pods
    echo -e "\n${BOLD}=== Check Complete ===${NC}"
}
main "$@"
