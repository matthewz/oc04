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
# 0. Infrastructure Prep
resource "null_resource" "prepare_env" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.out_dir}"
  }
}
resource "local_file" "helper_script" {
  depends_on      = [null_resource.prepare_env]
  filename        = "${local.out_dir}/helper.sh"
  file_permission = "0755"
  content         = templatefile("${path.module}/scripts/helper.sh.tpl", {
    generated_at = timestamp()
    out_dir      = abspath("${local.out_dir}")
    scripts_dir  = abspath("${path.module}/scripts")
    master_name  = local.master_name
    worker1_name = local.worker1_name
    worker2_name = local.worker2_name
    master_memory = var.master_memory
    master_cpus   = var.master_cpus
    worker_memory = var.worker_memory
    worker_cpus   = var.worker_cpus
    disk_size     = var.disk_size
  })
}
# --- STAGE 1: THE MASTER ---
# 1a. Create Master VM
resource "null_resource" "k8s_master" {
  depends_on = [null_resource.prepare_env, local_file.helper_script]
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh master ${local.master_name} ${var.master_memory} ${var.master_cpus} ${var.disk_size} ${local.out_dir}/master-ip.txt"
  }
}
# 1b. Install K8s Binaries on Master
resource "null_resource" "setup_common_master" {
  depends_on = [null_resource.k8s_master]
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.master_name} ${var.k8s_version}"
  }
}
# 1c. Initialize Cluster
resource "null_resource" "k8s_master_init" {
  depends_on = [null_resource.setup_common_master]
  provisioner "local-exec" {
    command = "MASTER_IP=$(cat ${local.out_dir}/master-ip.txt) && ${path.module}/scripts/init-master.sh ${local.master_name} $MASTER_IP ${var.pod_network_cidr} ${var.service_cidr} ${path.module}"
  }
}
# --- STAGE 2: WORKER 1 ---
# 2a. Create Worker 1 VM
resource "null_resource" "k8s_worker1" {
  depends_on = [null_resource.k8s_master_init] 
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker1_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${local.out_dir}/worker1-ip.txt"
  }
}
# 2b. Install K8s Binaries on Worker 1
resource "null_resource" "setup_common_worker1" {
  depends_on = [null_resource.k8s_worker1]
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker1_name} ${var.k8s_version}"
  }
}
# 2c. Join Worker 1 to Cluster
resource "null_resource" "k8s_worker1_join" {
  depends_on = [null_resource.setup_common_worker1]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker1_name} ${path.module}"
  }
}
# --- STAGE 3: WORKER 2 ---
# 3a. Create Worker 2 VM
resource "null_resource" "k8s_worker2" {
  depends_on = [null_resource.k8s_worker1_join] 
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-vm.sh worker ${local.worker2_name} ${var.worker_memory} ${var.worker_cpus} ${var.disk_size} ${local.out_dir}/worker2-ip.txt"
  }
}
# 3b. Install K8s Binaries on Worker 2
resource "null_resource" "setup_common_worker2" {
  depends_on = [null_resource.k8s_worker2]
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-k8s-common.sh ${local.worker2_name} ${var.k8s_version}"
  }
}
# 3c. Join Worker 2 to Cluster
resource "null_resource" "k8s_worker2_join" {
  depends_on = [null_resource.setup_common_worker2]
  provisioner "local-exec" {
    command = "${path.module}/scripts/join-worker.sh ${local.worker2_name} ${path.module}"
  }
}
# --- STAGE 4: FINALIZE ---
# 4. Pull Kubeconfig to local Mac
resource "null_resource" "setup_kubeconfig" {
  depends_on = [null_resource.k8s_worker2_join]
  provisioner "local-exec" {
    command = "MASTER_IP=$(cat ${local.out_dir}/master-ip.txt) && ${path.module}/scripts/setup-kubeconfig.sh ${local.master_name} $MASTER_IP config-k8s-multipass"
  }
}
