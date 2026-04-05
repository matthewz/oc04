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
output "helper_script_path" {
  value       = local_file.helper_script.filename
  description = "Path to the generated helper script"
}
output "master_ip" {
  value = multipass_instance.master.ipv4
}
output "worker_ips" {
  value = multipass_instance.workers[*].ipv4
}
output "ssh_command" {
  value = "multipass shell ${multipass_instance.master.name}"
}
