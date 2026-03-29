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
  out_dir      = "${path.module}/out"
}
# Ensure output directory exists
resource "null_resource" "prepare_env" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.out_dir}"
  }
}
# 1. Create Master
resource "null_resource" "k8s_master" {
  depends_on = [
    null_resource.prepare_env,
    local_file.helper_script,
  ]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh master ${local.master_name} ${var.master_memory} ${var.master_cpus} ${var.disk_size} ${local.out_dir}/master-ip.txt"
  }
}
# 2. Create Worker 1 (Only after Master is finished)
resource "null_resource" "k8s_worker1" {
  depends_on = [null_resource.k8s_master]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker1_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${local.out_dir}/worker1-ip.txt"
  }
}
# 3. Create Worker 2 (Only after Worker 1 is finished)
resource "null_resource" "k8s_worker2" {
  depends_on = [null_resource.k8s_worker1]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker2_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${local.out_dir}/worker2-ip.txt"
  }
}
# A. Generate helper.sh from template after the output dir exists
resource "local_file" "helper_script" {
  depends_on      = [null_resource.prepare_env]
  filename        = "${local.out_dir}/helper.sh"
  file_permission = "0755" # Make it executable right away
  content = templatefile("${path.module}/scripts/helper.sh.tpl", {
    # Metadata
    generated_at = timestamp()
    # Paths (absolute so the script works from any working directory)
    out_dir     = abspath("${local.out_dir}")
    scripts_dir = abspath("${path.module}/scripts")
    # Names
    master_name  = local.master_name
    worker1_name = local.worker1_name
    worker2_name = local.worker2_name
    # Sizing
    master_memory = var.master_memory
    master_cpus   = var.master_cpus
    worker_memory = var.worker_memory
    worker_cpus   = var.worker_cpus
    disk_size     = var.disk_size
  })
}
