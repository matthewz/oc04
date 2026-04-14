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
output "kubeconfig_setup" {
  value = "KUBECONFIG=~/.kube/config-k8s-multipass kubectl get nodes"
}
output "master_ip_address" {
  value = multipass_instance.master.ipv4
}
output "master_name" {
  value = multipass_instance.master.name
}
output "vault_ip" {
  value       = multipass_instance.vault.ipv4
  description = "Vault server IP — use this for VAULT_ADDR in helmfile"
}
output "vault_addr" {
  value       = "http://${multipass_instance.vault.ipv4}:8200"
  description = "Full Vault address — export as VAULT_ADDR"
}
output "vault_name" {
  value = multipass_instance.vault.name
}
output "vault_shell_command" {
  value = "multipass shell ${multipass_instance.vault.name}"
}
output "next_steps" {
  value = <<-EOT
    Vault VM is up. Now:
    1. export VAULT_ADDR=http://${multipass_instance.vault.ipv4}:8200
    2. bash ../scripts/init-vault.sh
    3. helmfile apply
  EOT
}
