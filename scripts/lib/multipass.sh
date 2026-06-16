#!/bin/bash
# =============================================================================
# scripts/lib/multipass.sh
# Wrapper functions for multipass exec and kubectl commands
# Usage: source "$(dirname "$0")/../lib/multipass.sh"
# =============================================================================
# -----------------------------------------------------------------------------
# vm_exec <vm_name> <command...>
# Run any command on a multipass VM as sudo
#
# Examples:
#   vm_exec "$MASTER_NAME" kubeadm token list
#   vm_exec "$WORKER_NAME" ip link show cni0
#   vm_exec "$WORKER_NAME" systemctl stop kubelet
# -----------------------------------------------------------------------------
vm_exec() {
    local vm="$1"
    shift
    multipass exec "$vm" -- sudo "$@"
}
# -----------------------------------------------------------------------------
# vm_exec_quiet <vm_name> <command...>
# Same as vm_exec but suppresses all output (useful for checks/polling)
# Uses subshell capture instead of &>/dev/null to avoid multipass TTY hang
#
# Examples:
#   vm_exec_quiet "$MASTER_NAME" kubeadm token list
#   if vm_exec_quiet "$WORKER_NAME" ip link show cni0; then ...
# -----------------------------------------------------------------------------
vm_exec_quiet() {
    local _out
    _out=$(vm_exec "$@" 2>&1)
    return $?
}
# -----------------------------------------------------------------------------
# kube_exec <vm_name> <kubectl args...>
# Run kubectl on a VM using the standard admin kubeconfig
#
# Examples:
#   kube_exec "$MASTER_NAME" get nodes
#   kube_exec "$MASTER_NAME" get node "$WORKER_NAME" --no-headers
#   kube_exec "$MASTER_NAME" delete node "$WORKER_NAME" --force --grace-period=0
# -----------------------------------------------------------------------------
kube_exec() {
    local vm="$1"
    shift
    vm_exec "$vm" kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
}
# -----------------------------------------------------------------------------
# kube_exec_quiet <vm_name> <kubectl args...>
# Same as kube_exec but suppresses all output
# Uses subshell capture instead of &>/dev/null to avoid multipass TTY hang
#
# Examples:
#   if kube_exec_quiet "$MASTER_NAME" get node "$WORKER_NAME"; then ...
# -----------------------------------------------------------------------------
kube_exec_quiet() {
    local _out
    _out=$(kube_exec "$@" 2>&1)
    return $?
}
# -----------------------------------------------------------------------------
# kube_get <vm_name> <resource> [extra args...]
# Convenience wrapper for kubectl get with --no-headers and stderr suppressed
# Returns the output as a string for use in conditionals or variables
#
# Examples:
#   kube_get "$MASTER_NAME" nodes
#   kube_get "$MASTER_NAME" node "$WORKER_NAME"
#   STATUS=$(kube_get "$MASTER_NAME" node "$WORKER_NAME")
# -----------------------------------------------------------------------------
kube_get() {
    local vm="$1"
    shift
    local _out
    _out=$(kube_exec "$vm" get "$@" --no-headers 2>&1)
    local _rc=$?
    echo "$_out"
    return $_rc
}
