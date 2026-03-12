#!/bin/bash
    
# Kubernetes Multipass Cluster Helper Script
    
export KUBECONFIG=~/.kube/config-k8s-multipass
    
# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
    
echo -e "${BLUE}Kubernetes Multipass Cluster Helper${NC}"
echo ""
    
# Show cluster info
show_cluster_info() {
  echo -e "${GREEN}Cluster Nodes:${NC}"
  kubectl get nodes -o wide
  echo ""
  echo -e "${GREEN}Cluster Info:${NC}"
  kubectl cluster-info
  echo ""
  echo -e "${GREEN}Multipass VMs:${NC}"
  multipass list
}
    
# SSH into nodes
ssh_master() {
  multipass shell k8s-master
}
    
ssh_worker1() {
  multipass shell k8s-worker1
}
    
ssh_worker2() {
  multipass shell k8s-worker2
}
    
# Show available commands
show_help() {
  echo "Available commands:"
  echo "  source k8s-helpers.sh        - Load this script"
  echo "  show_cluster_info            - Show cluster status"
  echo "  ssh_master                   - SSH into master node"
  echo "  ssh_worker1                  - SSH into worker1 node"
  echo "  ssh_worker2                  - SSH into worker2 node"
  echo ""
  echo "Kubectl is configured to use the cluster."
  echo "Try: kubectl get nodes"
}
    
# Auto-run info on source
if [ "${1}" != "--quiet" ]; then
  show_cluster_info
  echo ""
  show_help
fi
