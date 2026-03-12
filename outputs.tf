output "master_ip" {
  description = "IP address of the master node"
  value       = try(trimspace(data.local_file.master_ip.content), "pending")
}
output "worker1_ip" {
  description = "IP address of worker1 node"
  value       = try(trimspace(data.local_file.worker1_ip.content), "pending")
}
output "worker2_ip" {
  description = "IP address of worker2 node"
  value       = try(trimspace(data.local_file.worker2_ip.content), "pending")
}
output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    master_name  = local.master_name
    worker1_name = local.worker1_name
    worker2_name = local.worker2_name
    kubeconfig   = "~/.kube/config-k8s-multipass"
  }
}
output "helper_commands" {
  description = "Helpful commands to interact with the cluster"
  value       = <<-EOT
    # Load helper functions
    source k8s-helpers.sh
    
    # Or manually set kubeconfig
    export KUBECONFIG=~/.kube/config-k8s-multipass
    
    # Check cluster status
    kubectl get nodes
    kubectl cluster-info
    
    # SSH into nodes
    multipass shell ${local.master_name}
    multipass shell ${local.worker1_name}
    multipass shell ${local.worker2_name}
    
    # List all VMs
    multipass list
  EOT
}
