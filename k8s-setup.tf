# Create the "/out/ folder for ip.txt files...
resource "null_resource" "create_output_folder" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/out"
  }
}
# Wait for IP files to be created
data "local_file" "master_ip" {
  depends_on = [null_resource.k8s_master]
  filename   = "${path.module}/out/master-ip.txt"
}
data "local_file" "worker1_ip" {
  depends_on = [null_resource.k8s_worker1]
  filename   = "${path.module}/out/worker1-ip.txt"
}
data "local_file" "worker2_ip" {
  depends_on = [null_resource.k8s_worker2]
  filename   = "${path.module}/out/worker2-ip.txt"
}
# Install Kubernetes on all nodes
resource "null_resource" "k8s_common_setup" {
  depends_on = [
    null_resource.k8s_master,
    null_resource.k8s_worker1,
    null_resource.k8s_worker2
  ]
  # Install on master
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.master_name} ${var.k8s_version} ${var.pod_network_cidr}"
  }
  # Install on worker1
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker1_name} ${var.k8s_version} ${var.pod_network_cidr}"
  }
  # Install on worker2
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker2_name} ${var.k8s_version} ${var.pod_network_cidr}"
  }
}
# Initialize Kubernetes master
resource "null_resource" "k8s_master_init" {
  depends_on = [null_resource.k8s_common_setup]
  provisioner "local-exec" {
    command = "${path.module}/scripts/init-master.sh ${local.master_name} ${trimspace(data.local_file.master_ip.content)} ${var.pod_network_cidr} ${var.service_cidr} ${path.module}"
  }
}
# Join worker1 to cluster
resource "null_resource" "k8s_worker1_join" {
  depends_on = [null_resource.k8s_master_init]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker1_name} ${local.master_name}"
  }
}
# Join worker2 to cluster
resource "null_resource" "k8s_worker2_join" {
  depends_on = [null_resource.k8s_master_init]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker2_name} ${local.master_name}"
  }
}
# Setup local kubeconfig
resource "null_resource" "setup_kubeconfig" {
  depends_on = [
    null_resource.k8s_worker1_join,
    null_resource.k8s_worker2_join
  ]
  provisioner "local-exec" {
    command = "${path.module}/scripts/setup-kubeconfig.sh ${local.master_name} ${trimspace(data.local_file.master_ip.content)} config-k8s-multipass"
  }
}
# Create helper script
resource "local_file" "k8s_helpers" {
  depends_on = [null_resource.setup_kubeconfig]

  filename        = "${path.module}/util/k8s-helpers.sh"
  file_permission = "0755"

  content = <<-EOT
    #!/bin/bash
    
    # Kubernetes Multipass Cluster Helper Script
    
    export KUBECONFIG=~/.kube/config-k8s-multipass
    
    # Colors
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
    
    echo -e "$${BLUE}Kubernetes Multipass Cluster Helper$${NC}"
    echo ""
    
    # Show cluster info
    show_cluster_info() {
      echo -e "$${GREEN}Cluster Nodes:$${NC}"
      kubectl get nodes -o wide
      echo ""
      echo -e "$${GREEN}Cluster Info:$${NC}"
      kubectl cluster-info
      echo ""
      echo -e "$${GREEN}Multipass VMs:$${NC}"
      multipass list
    }
    
    # SSH into nodes
    ssh_master() {
      multipass shell ${local.master_name}
    }
    
    ssh_worker1() {
      multipass shell ${local.worker1_name}
    }
    
    ssh_worker2() {
      multipass shell ${local.worker2_name}
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
    if [ "$${1}" != "--quiet" ]; then
      show_cluster_info
      echo ""
      show_help
    fi
  EOT
}
