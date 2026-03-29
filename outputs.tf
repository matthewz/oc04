output "cluster_status" {
  value = "Provisioning Complete."
}
output "verification_commands" {
  value = <<-EOT
    # Run these to access your cluster:
    export KUBECONFIG=~/.kube/config-k8s-multipass
    kubectl get nodes
  EOT
}
