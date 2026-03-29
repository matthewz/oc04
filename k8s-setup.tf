# Install Kubernetes on all nodes (Common binaries)
resource "null_resource" "k8s_common_setup" {
  depends_on = [
    null_resource.k8s_master,
    null_resource.k8s_worker1,
    null_resource.k8s_worker2
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.master_name} ${var.k8s_version}"
  }
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker1_name} ${var.k8s_version}"
  }
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker2_name} ${var.k8s_version}"
  }
}
# Initialize Kubernetes master
resource "null_resource" "k8s_master_init" {
  depends_on = [null_resource.k8s_common_setup]
  provisioner "local-exec" {
    command = <<EOT
      export MASTER_IP=$(cat ${path.module}/out/master-ip.txt)
      ${path.module}/scripts/init-master.sh ${local.master_name} $MASTER_IP ${var.pod_network_cidr} ${var.service_cidr} ${path.module}
    EOT
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
  depends_on = [null_resource.k8s_worker1_join]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker2_name} ${local.master_name}"
  }
}
# Setup local kubeconfig
resource "null_resource" "setup_kubeconfig" {
  depends_on = [null_resource.k8s_worker2_join]
  provisioner "local-exec" {
    command = "export MASTER_IP=$(cat ${path.module}/out/master-ip.txt) && ${path.module}/scripts/setup-kubeconfig.sh ${local.master_name} $MASTER_IP config-k8s-multipass"
  }
}
