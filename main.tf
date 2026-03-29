terraform {
  required_version = ">= 1.0"
  required_providers {
    null  = { source = "hashicorp/null", version = "~> 3.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}
locals {
  master_name  = "k8s-master"
  worker1_name = "k8s-worker1"
  worker2_name = "k8s-worker2"
}
# This provides the folder that everyone else depends on
resource "null_resource" "create_output_folder" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/out"
  }
}
resource "null_resource" "k8s_master" {
  depends_on = [null_resource.create_output_folder]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh master ${local.master_name} ${var.master_memory} ${var.master_cpus} ${var.disk_size} ${path.module}/out/master-ip.txt"
  }
}
resource "null_resource" "k8s_worker1" {
  depends_on = [null_resource.k8s_master]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker1_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${path.module}/out/worker1-ip.txt"
  }
}
resource "null_resource" "k8s_worker2" {
  depends_on = [null_resource.k8s_worker1]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker2_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${path.module}/out/worker2-ip.txt"
  }
}
