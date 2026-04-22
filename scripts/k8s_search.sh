#!/bin/bash
# ============================================================
# k8s-search.sh
# Search for Kubernetes resources by name pattern and report health
# Usage: ./k8s-search.sh <search_term> [namespace]
#        ./k8s-search.sh claw
#        ./k8s-search.sh claw my-namespace
# ============================================================
set -euo pipefail
# ── Colours ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Colour
# ── Arguments ──────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: $0 <search_term> [namespace]${NC}"
  echo -e "${DIM}  search_term : string to match against resource names${NC}"
  echo -e "${DIM}  namespace   : (optional) limit search to one namespace${NC}"
  exit 1
fi
SEARCH_TERM="${1}"
NAMESPACE_FLAG="--all-namespaces"
NAMESPACE_LABEL="all namespaces"
if [[ -n "${2:-}" ]]; then
  NAMESPACE_FLAG="-n ${2}"
  NAMESPACE_LABEL="namespace: ${2}"
fi
# ── Counters ───────────────────────────────────────────────
TOTAL_FOUND=0
TOTAL_HEALTHY=0
TOTAL_UNHEALTHY=0
TOTAL_UNKNOWN=0
# ── Helper: section header ─────────────────────────────────
print_header() {
  local resource_type="$1"
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  🔍 ${resource_type}${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
# ── Helper: health badge ───────────────────────────────────
health_badge() {
  local status="$1"
  case "$status" in
    HEALTHY)   echo -e "${GREEN}${BOLD}[✔ HEALTHY]${NC}" ;;
    UNHEALTHY) echo -e "${RED}${BOLD}[✘ UNHEALTHY]${NC}" ;;
    *)         echo -e "${YELLOW}${BOLD}[? UNKNOWN]${NC}" ;;
  esac
}
# ── Helper: increment counters ─────────────────────────────
tally() {
  local status="$1"
  ((TOTAL_FOUND++))
  case "$status" in
    HEALTHY)   ((TOTAL_HEALTHY++)) ;;
    UNHEALTHY) ((TOTAL_UNHEALTHY++)) ;;
    *)         ((TOTAL_UNKNOWN++)) ;;
  esac
}
# ============================================================
# DEPLOYMENTS
# ============================================================
check_deployments() {
  print_header "DEPLOYMENTS"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get deployments $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas,UPDATED:.status.updatedReplicas" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No deployments found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name ready desired available updated
    ns=$(echo "$line"      | awk '{print $1}')
    name=$(echo "$line"    | awk '{print $2}')
    ready=$(echo "$line"   | awk '{print $3}')
    desired=$(echo "$line" | awk '{print $4}')
    # Treat <none> / empty as 0
    [[ "$ready"   == "<none>" || -z "$ready"   ]] && ready=0
    [[ "$desired" == "<none>" || -z "$desired" ]] && desired=0
    local health="UNKNOWN"
    local reason=""
    if [[ "$desired" -gt 0 && "$ready" -eq "$desired" ]]; then
      health="HEALTHY"
      reason="All ${desired}/${desired} replicas ready"
    elif [[ "$desired" -eq 0 ]]; then
      health="UNKNOWN"
      reason="Scaled to zero — intentional?"
    else
      health="UNHEALTHY"
      reason="${ready}/${desired} replicas ready"
    fi
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    # Full kubectl output for context
    echo -e "${DIM}"
    # shellcheck disable=SC2086
    kubectl get deployment "$name" -n "$ns" \
      -o wide 2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# PODS
# ============================================================
check_pods() {
  print_header "PODS"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get pods $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No pods found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name ready status restarts
    ns=$(echo "$line"       | awk '{print $1}')
    name=$(echo "$line"     | awk '{print $2}')
    ready=$(echo "$line"    | awk '{print $3}')   # true/false/true,false
    status=$(echo "$line"   | awk '{print $4}')
    restarts=$(echo "$line" | awk '{print $5}')
    local health="UNKNOWN"
    local reason=""
    # Check if all containers are ready (all values = "true")
    if [[ "$status" == "Running" ]] && ! echo "$ready" | grep -qi "false"; then
      health="HEALTHY"
      reason="Phase: Running | All containers ready | Restarts: ${restarts}"
    elif [[ "$status" == "Succeeded" ]]; then
      health="HEALTHY"
      reason="Phase: Succeeded (completed job)"
    elif [[ "$status" == "Pending" ]]; then
      health="UNHEALTHY"
      reason="Phase: Pending — may be scheduling or init issue"
    elif [[ "$status" == "Failed" || "$status" == "CrashLoopBackOff" ]]; then
      health="UNHEALTHY"
      reason="Phase: ${status}"
    else
      health="UNHEALTHY"
      reason="Phase: ${status} | Ready: ${ready} | Restarts: ${restarts}"
    fi
    # High restarts are a red flag even if "running"
    local max_restarts
    max_restarts=$(echo "$restarts" | tr ',' '\n' | sort -n | tail -1)
    if [[ "$max_restarts" =~ ^[0-9]+$ && "$max_restarts" -gt 5 ]]; then
      health="UNHEALTHY"
      reason="${reason} ⚠️  High restart count: ${max_restarts}"
    fi
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get pod "$name" -n "$ns" \
      -o wide 2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# REPLICA SETS
# ============================================================
check_replicasets() {
  print_header "REPLICA SETS"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get replicasets $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.replicas,READY:.status.readyReplicas" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No replica sets found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name desired current ready
    ns=$(echo "$line"      | awk '{print $1}')
    name=$(echo "$line"    | awk '{print $2}')
    desired=$(echo "$line" | awk '{print $3}')
    current=$(echo "$line" | awk '{print $4}')
    ready=$(echo "$line"   | awk '{print $5}')
    [[ "$ready"   == "<none>" || -z "$ready"   ]] && ready=0
    [[ "$desired" == "<none>" || -z "$desired" ]] && desired=0
    local health reason
    if [[ "$desired" -eq 0 ]]; then
      health="UNKNOWN"
      reason="Desired replicas = 0 (likely an old RS from a deployment rollout)"
    elif [[ "$ready" -eq "$desired" ]]; then
      health="HEALTHY"
      reason="${ready}/${desired} replicas ready"
    else
      health="UNHEALTHY"
      reason="${ready}/${desired} replicas ready"
    fi
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get replicaset "$name" -n "$ns" \
      -o wide 2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# SERVICES
# ============================================================
check_services() {
  print_header "SERVICES"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get services $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip,PORT:.spec.ports[*].port" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No services found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name svc_type cluster_ip external_ip
    ns=$(echo "$line"          | awk '{print $1}')
    name=$(echo "$line"        | awk '{print $2}')
    svc_type=$(echo "$line"    | awk '{print $3}')
    cluster_ip=$(echo "$line"  | awk '{print $4}')
    external_ip=$(echo "$line" | awk '{print $5}')
    local health reason
    # Services don't have a direct "phase" — we infer from type + IP
    if [[ "$cluster_ip" == "None" ]]; then
      health="HEALTHY"
      reason="Headless service (ClusterIP: None) — by design"
    elif [[ "$svc_type" == "LoadBalancer" && ( -z "$external_ip" || "$external_ip" == "<none>" ) ]]; then
      health="UNHEALTHY"
      reason="LoadBalancer type but no External IP assigned — pending or misconfigured"
    elif [[ -n "$cluster_ip" && "$cluster_ip" != "<none>" ]]; then
      health="HEALTHY"
      reason="Type: ${svc_type} | ClusterIP: ${cluster_ip}"
    else
      health="UNKNOWN"
      reason="Could not determine IP assignment"
    fi
    # Check that the service has at least one endpoint
    local ep_count
    ep_count=$(kubectl get endpoints "$name" -n "$ns" \
               -o jsonpath='{.subsets[*].addresses}' 2>/dev/null | tr ',' '\n' | grep -c 'ip' || echo 0)
    if [[ "$ep_count" -eq 0 && "$cluster_ip" != "None" ]]; then
      health="UNHEALTHY"
      reason="${reason} ⚠️  No endpoints — selector may not match any pods"
    fi
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get service "$name" -n "$ns" \
      -o wide 2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# INGRESSES
# ============================================================
check_ingresses() {
  print_header "INGRESSES"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get ingress $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,ADDRESS:.status.loadBalancer.ingress[0].ip" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No ingresses found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name class hosts address
    ns=$(echo "$line"      | awk '{print $1}')
    name=$(echo "$line"    | awk '{print $2}')
    class=$(echo "$line"   | awk '{print $3}')
    hosts=$(echo "$line"   | awk '{print $4}')
    address=$(echo "$line" | awk '{print $5}')
    local health reason
    if [[ -n "$address" && "$address" != "<none>" ]]; then
      health="HEALTHY"
      reason="Has address: ${address} | Host(s): ${hosts} | Class: ${class}"
    else
      health="UNHEALTHY"
      reason="No address assigned — ingress controller may be missing or misconfigured"
    fi
    tally "$health"
    echo -e
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get ingress "$name" -n "$ns" \
      -o wide 2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# CONFIG MAPS
# ============================================================
check_configmaps() {
  print_header "CONFIG MAPS"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get configmaps $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,DATA:.data" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No config maps found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name data
    ns=$(echo "$line"   | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    data=$(echo "$line" | awk '{print $3}')
    local health reason
    # ConfigMaps don't have a health state per se — we check if they have data
    if [[ -z "$data" || "$data" == "<none>" ]]; then
      health="UNKNOWN"
      reason="ConfigMap exists but contains no data keys — possibly intentional"
    else
      health="HEALTHY"
      reason="ConfigMap exists and contains data"
    fi
    # Count actual keys
    local key_count
    key_count=$(kubectl get configmap "$name" -n "$ns" \
                -o jsonpath='{.data}' 2>/dev/null | python3 -c \
                "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "?")
    reason="${reason} | Keys: ${key_count}"
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get configmap "$name" -n "$ns" \
      2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# SECRETS
# ============================================================
check_secrets() {
  print_header "SECRETS"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get secrets $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,TYPE:.type,DATA:.data" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No secrets found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name secret_type data
    ns=$(echo "$line"           | awk '{print $1}')
    name=$(echo "$line"         | awk '{print $2}')
    secret_type=$(echo "$line"  | awk '{print $3}')
    data=$(echo "$line"         | awk '{print $4}')
    local health reason
    if [[ -z "$data" || "$data" == "<none>" ]]; then
      health="UNKNOWN"
      reason="Secret exists but has no data — possibly an empty placeholder"
    else
      health="HEALTHY"
      reason="Secret exists | Type: ${secret_type}"
    fi
    # Count keys without revealing values
    local key_count
    key_count=$(kubectl get secret "$name" -n "$ns" \
                -o jsonpath='{.data}' 2>/dev/null | python3 -c \
                "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "?")
    reason="${reason} | Keys: ${key_count} (values redacted)"
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    # Show metadata only — never show secret data
    echo -e "${DIM}"
    kubectl get secret "$name" -n "$ns" \
      2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# NAMESPACES
# ============================================================
check_namespaces() {
  print_header "NAMESPACES"
  local raw
  raw=$(kubectl get namespaces \
        --no-headers \
        -o custom-columns="NAME:.metadata.name,STATUS:.status.phase" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No namespaces found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local name ns_status
    name=$(echo "$line"      | awk '{print $1}')
    ns_status=$(echo "$line" | awk '{print $2}')
    local health reason
    if [[ "$ns_status" == "Active" ]]; then
      health="HEALTHY"
      reason="Namespace is Active"
    elif [[ "$ns_status" == "Terminating" ]]; then
      health="UNHEALTHY"
      reason="Namespace is Terminating — may be stuck waiting on finalizers"
    else
      health="UNKNOWN"
      reason="Status: ${ns_status}"
    fi
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get namespace "$name" \
      2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# NETWORK POLICIES
# ============================================================
check_networkpolicies() {
  print_header "NETWORK POLICIES"
  local raw
  # shellcheck disable=SC2086
  raw=$(kubectl get networkpolicies $NAMESPACE_FLAG \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,POD-SELECTOR:.spec.podSelector" \
        2>/dev/null | grep -i "$SEARCH_TERM" || true)
  if [[ -z "$raw" ]]; then
    echo -e "${DIM}  No network policies found matching '${SEARCH_TERM}'${NC}"
    return
  fi
  while IFS= read -r line; do
    local ns name pod_selector
    ns=$(echo "$line"           | awk '{print $1}')
    name=$(echo "$line"         | awk '{print $2}')
    pod_selector=$(echo "$line" | awk '{print $3}')
    local health reason
    # Pull ingress + egress rule counts via jsonpath
    local ingress_rules egress_rules
    ingress_rules=$(kubectl get networkpolicy "$name" -n "$ns" \
                    -o jsonpath='{.spec.ingress}' 2>/dev/null | \
                    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo 0)
    egress_rules=$(kubectl get networkpolicy "$name" -n "$ns" \
                   -o jsonpath='{.spec.egress}' 2>/dev/null | \
                   python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo 0)
    # A NetworkPolicy with an empty podSelector ({}) applies to ALL pods in the namespace
    if [[ "$pod_selector" == "{}" || "$pod_selector" == "map[]" ]]; then
      health="UNKNOWN"
      reason="⚠️  Empty podSelector — policy applies to ALL pods in namespace '${ns}'"
    else
      health="HEALTHY"
      reason="Policy exists | PodSelector: ${pod_selector}"
    fi
    reason="${reason} | Ingress rules: ${ingress_rules} | Egress rules: ${egress_rules}"
    tally "$health"
    echo -e "  $(health_badge "$health")  ${BOLD}${name}${NC}  ${DIM}(ns: ${ns})${NC}"
    echo -e "            ${DIM}↳ ${reason}${NC}"
    echo -e "${DIM}"
    kubectl get networkpolicy "$name" -n "$ns" \
      2>/dev/null | sed 's/^/            /'
    echo -e "${NC}"
  done <<< "$raw"
}
# ============================================================
# SUMMARY
# ============================================================
print_summary() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  📊 SUMMARY  —  search: '${SEARCH_TERM}'  (${NAMESPACE_LABEL})${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Total resources found : ${BOLD}${TOTAL_FOUND}${NC}"
  echo -e "  ${GREEN}${BOLD}✔ Healthy${NC}             : ${TOTAL_HEALTHY}"
  echo -e "  ${RED}${BOLD}✘ Unhealthy${NC}           : ${TOTAL_UNHEALTHY}"
  echo -e "  ${YELLOW}${BOLD}? Unknown${NC}             : ${TOTAL_UNKNOWN}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  if [[ "$TOTAL_UNHEALTHY" -gt 0 ]]; then
    exit 1   # non-zero exit so CI pipelines can catch unhealthy state
  fi
}
# ============================================================
# MAIN
# ============================================================
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        Kubernetes Resource Health Scanner          ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════╝${NC}"
echo -e "  Search term : ${CYAN}${BOLD}${SEARCH_TERM}${NC}"
echo -e "  Scope       : ${CYAN}${BOLD}${NAMESPACE_LABEL}${NC}"
set -x
check_deployments
check_pods
check_replicasets
check_services
check_ingresses
check_configmaps
check_secrets
check_namespaces
check_networkpolicies
print_summary
