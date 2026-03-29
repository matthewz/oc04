#!/usr/bin/env bash
# =============================================================================
# Kubernetes Dashboard Setup Script
# =============================================================================
# Usage: ./setup-dashboard.sh
# Requirements: kubectl, lsof, base64
# =============================================================================
set -euo pipefail
# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly DASHBOARD_VERSION="v2.7.0"
readonly DASHBOARD_MANIFEST="https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml"
readonly NAMESPACE="kubernetes-dashboard"
readonly SERVICE_ACCOUNT="admin-user"
readonly SECRET_NAME="admin-user-token"
readonly TOKEN_FILE="./dashboard-token.txt"
readonly PROXY_PORT="8001"
readonly FORWARD_PORT="8443"
readonly NODE_PORT="30443"
readonly TOKEN_TTL="288000"
# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo "============================================"
    echo "🚀 $1"
    echo "============================================"
}
print_info()    { echo "  ℹ️  $*"; }
print_success() { echo "  ✅ $*"; }
print_warning() { echo "  ⚠️  $*"; }
print_error()   { echo "  ❌ $*" >&2; }
run() {
    echo "  + $*"
    "$@"
}
resource_exists() {
    kubectl get "$@" &>/dev/null
}
wait_for_deployment() {
    local ns="$1"
    local name="$2"
    local timeout="${3:-120s}"
    print_info "Waiting for deployment/${name} to be ready (timeout: ${timeout})..."
    if ! kubectl rollout status deployment/"${name}" \
            -n "${ns}" \
            --timeout="${timeout}"; then
        print_error "Deployment ${name} did not become ready in time."
        kubectl get events -n "${ns}" --sort-by='.lastTimestamp' | tail -20
        return 1
    fi
    print_success "Deployment ${name} is ready."
}
free_port() {
    local port="$1"
    local pids
    pids=$(lsof -t -i :"${port}" 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then
        print_warning "Port ${port} is in use (PIDs: ${pids}). Killing..."
        # shellcheck disable=SC2086
        kill -9 ${pids} 2>/dev/null || true
        sleep 1
    fi
}
require_cmd() {
    for cmd in "$@"; do
        if ! command -v "${cmd}" &>/dev/null; then
            print_error "Required command not found: ${cmd}"
            exit 1
        fi
    done
}
# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
preflight_checks() {
    print_header "Preflight Checks"
    require_cmd kubectl lsof base64
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot reach the Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    print_success "Cluster is reachable."
    print_info "Current context: $(kubectl config current-context)"
}
# -----------------------------------------------------------------------------
# Step 1 — Teardown (idempotent)
# -----------------------------------------------------------------------------
teardown() {
    print_header "Tearing Down Previous Installation (if any)"
    print_info "Removing ClusterRoleBinding..."
    kubectl delete clusterrolebinding "${SERVICE_ACCOUNT}" \
        --ignore-not-found=true 2>/dev/null || true
    print_info "Removing namespace-scoped resources..."
    kubectl delete secret "${SECRET_NAME}" \
        -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    kubectl delete serviceaccount "${SERVICE_ACCOUNT}" \
        -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    print_info "Removing dashboard manifest resources..."
    kubectl delete -f "${DASHBOARD_MANIFEST}" \
        --ignore-not-found=true 2>/dev/null || true
    if resource_exists namespace "${NAMESPACE}"; then
        print_info "Deleting namespace ${NAMESPACE} (may take a moment)..."
        kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
        local attempts=0
        while resource_exists namespace "${NAMESPACE}"; do
            (( attempts++ ))
            if (( attempts > 30 )); then
                print_error "Namespace ${NAMESPACE} still terminating after 60s. Aborting."
                exit 1
            fi
            echo -n "."
            sleep 2
        done
        echo ""
    else
        print_info "Namespace ${NAMESPACE} not found — nothing to delete."
    fi
    print_success "Teardown complete."
}
# -----------------------------------------------------------------------------
# Step 2 — Namespace & context
# -----------------------------------------------------------------------------
setup_namespace_and_context() {
    print_header "Creating Namespace & Setting Context"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
    print_info "Current contexts:"
    kubectl config get-contexts
    print_info "Setting default namespace to ${NAMESPACE}..."
    run kubectl config set-context --current --namespace="${NAMESPACE}"
    print_success "Active context: $(kubectl config current-context)"
}
# -----------------------------------------------------------------------------
# Step 3 — Install Dashboard
# -----------------------------------------------------------------------------
install_dashboard() {
    print_header "Installing Kubernetes Dashboard ${DASHBOARD_VERSION}"
    run kubectl apply -f "${DASHBOARD_MANIFEST}"
    echo ""
    wait_for_deployment "${NAMESPACE}" "kubernetes-dashboard" "180s"
    echo ""
    print_info "Pods:"
    kubectl -n "${NAMESPACE}" get pods
    echo ""
    print_info "Services:"
    kubectl -n "${NAMESPACE}" get svc
}
# -----------------------------------------------------------------------------
# Step 4 — RBAC & token
# -----------------------------------------------------------------------------
setup_rbac_and_token() {
    print_header "Creating ServiceAccount, RBAC & Token"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
EOF
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SERVICE_ACCOUNT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
EOF
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT}
type: kubernetes.io/service-account-token
EOF
    print_info "Waiting for token to be populated in secret..."
    local attempts=0
    until kubectl get secret "${SECRET_NAME}" \
            -n "${NAMESPACE}" \
            -o jsonpath="{.data.token}" 2>/dev/null | grep -q .; do
        (( attempts++ ))
        if (( attempts > 15 )); then
            print_error "Token was not populated after 30s."
            exit 1
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    print_info "Verifying resources:"
    run kubectl get serviceaccount "${SERVICE_ACCOUNT}" -n "${NAMESPACE}"
    run kubectl get clusterrolebinding "${SERVICE_ACCOUNT}"
    run kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}"
    kubectl get secret "${SECRET_NAME}" \
        -n "${NAMESPACE}" \
        -o jsonpath="{.data.token}" \
        | base64 --decode \
        > "${TOKEN_FILE}"
    echo ""
    print_success "Token saved to ${TOKEN_FILE}"
    print_info "Token JWT payload:"
    cut -d. -f2 "${TOKEN_FILE}" \
        | base64 --decode 2>/dev/null \
        | python3 -m json.tool 2>/dev/null \
        || true
}
# -----------------------------------------------------------------------------
# Step 5 — Patch dashboard deployment
# -----------------------------------------------------------------------------
patch_dashboard() {
    print_header "Patching Dashboard Deployment"
    add_arg_if_missing() {
        local arg="$1"
        local current_args
        current_args=$(kubectl get deployment kubernetes-dashboard \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.containers[0].args}')
        if echo "${current_args}" | grep -q "${arg}"; then
            print_info "Arg already present, skipping: ${arg}"
        else
            print_info "Adding arg: ${arg}"
            run kubectl patch deployment kubernetes-dashboard \
                -n "${NAMESPACE}" \
                --type="json" \
                -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"${arg}\"}]"
        fi
    }
    add_arg_if_missing "--enable-skip-login"
    add_arg_if_missing "--token-ttl=${TOKEN_TTL}"
    print_info "Waiting for patched deployment to roll out..."
    wait_for_deployment "${NAMESPACE}" "kubernetes-dashboard" "120s"
    print_info "Final container args:"
    kubectl get deployment kubernetes-dashboard \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].args}' \
        | tr ',' '\n'
    echo ""
    print_info "Pod logs (last 20 lines):"
    kubectl logs -n "${NAMESPACE}" \
        deployment/kubernetes-dashboard \
        --tail=20 \
        2>/dev/null || print_warning "Logs not yet available."
}
# -----------------------------------------------------------------------------
# Step 6 — Expose via NodePort
# -----------------------------------------------------------------------------
expose_nodeport() {
    print_header "Exposing Dashboard via NodePort ${NODE_PORT}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    k8s-app: kubernetes-dashboard
  ports:
  - port: 443
    targetPort: 8443
    nodePort: ${NODE_PORT}
    protocol: TCP
EOF
    print_info "Node IPs:"
    kubectl get nodes -o wide
    echo ""
    print_success "NodePort access: https://<NODE_IP>:${NODE_PORT}"
}
# -----------------------------------------------------------------------------
# Step 7 — Start port-forward
# -----------------------------------------------------------------------------
start_port_forward() {
    print_header "Starting Port-Forward on localhost:${FORWARD_PORT}"
    local pids
    pids=$(lsof -t -i :"${FORWARD_PORT}" 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then
        print_warning "Killing existing process on port ${FORWARD_PORT} (PIDs: ${pids})"
        # shellcheck disable=SC2086
        kill -9 ${pids} 2>/dev/null || true
        sleep 1
    fi
    kubectl port-forward \
        -n "${NAMESPACE}" \
        svc/kubernetes-dashboard \
        "${FORWARD_PORT}":443 \
        > /tmp/dashboard-portforward.log 2>&1 &
    local pf_pid=$!
    echo "${pf_pid}" > /tmp/dashboard-portforward.pid
    sleep 2
    if ! kill -0 "${pf_pid}" 2>/dev/null; then
        print_error "Port-forward failed to start. Log output:"
        cat /tmp/dashboard-portforward.log
        return 1
    fi
    print_success "Port-forward running (PID: ${pf_pid})"
    print_info "Log:      /tmp/dashboard-portforward.log"
    print_info "PID file: /tmp/dashboard-portforward.pid"
}
# -----------------------------------------------------------------------------
# Step 8 — Start kubectl proxy
# -----------------------------------------------------------------------------
start_proxy() {
    print_header "Starting kubectl proxy on localhost:${PROXY_PORT}"
    local pids
    pids=$(lsof -t -i :"${PROXY_PORT}" 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then
        print_warning "Killing existing process on port ${PROXY_PORT} (PIDs: ${pids})"
        # shellcheck disable=SC2086
        kill -9 ${pids} 2>/dev/null || true
        sleep 1
    fi
    kubectl proxy \
        > /tmp/dashboard-proxy.log 2>&1 &
    local proxy_pid=$!
    echo "${proxy_pid}" > /tmp/dashboard-proxy.pid
    sleep 2
    if ! kill -0 "${proxy_pid}" 2>/dev/null; then
        print_warning "kubectl proxy failed to start (non-fatal). Log:"
        cat /tmp/dashboard-proxy.log
        return 0
    fi
    print_success "kubectl proxy running (PID: ${proxy_pid})"
    print_info "Log:      /tmp/dashboard-proxy.log"
    print_info "PID file: /tmp/dashboard-proxy.pid"
}
# -----------------------------------------------------------------------------
# Step 9 — Final summary
# -----------------------------------------------------------------------------
final_summary() {
    print_header "Final Resource Summary"
    print_info "All resources in ${NAMESPACE}:"
    kubectl get all -n "${NAMESPACE}"
    echo ""
    print_info "ServiceAccount:"
    kubectl get serviceaccount "${SERVICE_ACCOUNT}" -n "${NAMESPACE}"
    echo ""
    print_info "ClusterRoleBinding:"
    kubectl get clusterrolebinding "${SERVICE_ACCOUNT}"
    echo ""
    print_info "Recent events (last 10):"
    kubectl get events \
        -n "${NAMESPACE}" \
        --sort-by='.lastTimestamp' \
        2>/dev/null | tail -10
    echo ""
    # Grab the first node's internal IP for the NodePort URL
    local node_ip
    node_ip=$(kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
        2>/dev/null || echo "<NODE_IP>")
    print_header "Access Summary"
    echo ""
    echo "  🌐 Port-forward ......... https://localhost:${FORWARD_PORT}"
    echo "                            ⚠️  Accept the self-signed certificate warning"
    echo ""
    echo "  🌐 kubectl proxy ........ http://localhost:${PROXY_PORT}/api/v1/namespaces/${NAMESPACE}/services/https:kubernetes-dashboard:/proxy/"
    echo ""
    echo "  🌐 NodePort ............. https://${node_ip}:${NODE_PORT}"
    echo "                            ⚠️  Accept the self-signed certificate warning"
    echo ""
    echo "  🔑 Print token .......... cat ${TOKEN_FILE}"
    echo ""
    echo "  🛑 Stop port-forward .... kill \$(cat /tmp/dashboard-portforward.pid)"
    echo "  🛑 Stop proxy ........... kill \$(cat /tmp/dashboard-proxy.pid)"
    echo ""
}
# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    preflight_checks
    teardown
    setup_namespace_and_context
    install_dashboard
    setup_rbac_and_token
    patch_dashboard
    expose_nodeport
    start_port_forward
    start_proxy
    final_summary
    print_header "Done 🎉"
}
main "$@"
