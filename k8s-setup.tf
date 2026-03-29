# Install Common Binaries - Master
resource "null_resource" "setup_common_master" {
  depends_on = [null_resource.k8s_worker2] # Wait for all VMs to exist first
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.master_name} ${var.k8s_version}"
  }
}
# Initialize Master
resource "null_resource" "k8s_master_init" {
  depends_on = [null_resource.setup_common_master]
  provisioner "local-exec" {
    command = <<EOT
      MASTER_IP=$(cat ${local.out_dir}/master-ip.txt)
      ${path.module}/scripts/init-master.sh ${local.master_name} $MASTER_IP ${var.pod_network_cidr} ${var.service_cidr} ${path.module}
    EOT
  }
}
# Install Common Binaries - Worker 1
resource "null_resource" "setup_common_worker1" {
  depends_on = [null_resource.k8s_master_init]
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker1_name} ${var.k8s_version}"
  }
}
# Join Worker 1
resource "null_resource" "k8s_worker1_join" {
  depends_on = [null_resource.setup_common_worker1]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker1_name} ${local.master_name}"
  }
}
# Install Common Binaries - Worker 2
resource "null_resource" "setup_common_worker2" {
  depends_on = [null_resource.k8s_worker1_join]
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker2_name} ${var.k8s_version}"
  }
}
# Join Worker 2
resource "null_resource" "k8s_worker2_join" {
  depends_on = [null_resource.setup_common_worker2]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker2_name} ${local.master_name}"
  }
}
# Final Kubeconfig setup
resource "null_resource" "setup_kubeconfig" {
  depends_on = [null_resource.k8s_worker2_join]
  provisioner "local-exec" {
    command = "MASTER_IP=$(cat ${local.out_dir}/master-ip.txt) && ${path.module}/scripts/setup-kubeconfig.sh ${local.master_name} $MASTER_IP config-k8s-multipass"
  }
}
