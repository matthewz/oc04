terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}
locals {
  master_name  = "k8s-master"
  worker1_name = "k8s-worker1"
  worker2_name = "k8s-worker2"
}
# Create master node
resource "null_resource" "k8s_master" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-master.sh ${local.master_name} ${var.master_memory} ${var.master_cpus} ${var.disk_size} ${path.module}/out/master-ip.txt"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete k8s-master --purge || true"
  }
}
# Create worker1 node
resource "null_resource" "k8s_worker1" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-worker.sh ${local.worker1_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${path.module}/out/worker1-ip.txt"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete k8s-worker1 --purge || true"
  }
}
# Create worker2 node
resource "null_resource" "k8s_worker2" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-worker.sh ${local.worker2_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${path.module}/out/worker2-ip.txt"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete k8s-worker2 --purge || true"
  }
}
