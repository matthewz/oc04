terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4.2"
    }
  }
}
locals {
  out_dir      = "out"
  master_name  = "k8s-master"
  worker1_name = "k8s-worker-1"
  worker2_name = "k8s-worker-2"
  image_to_use = (var.k8s_golden_image != "" && fileexists(var.k8s_golden_image)) ? "file://${abspath(var.k8s_golden_image)}" : "22.04"
}
resource "null_resource" "prepare_env" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.out_dir}"
  }
}
resource "local_file" "helper_script" {
  depends_on      = [null_resource.prepare_env]
  filename        = "${local.out_dir}/helper.sh"
  file_permission = "0755"
  content = templatefile("${path.module}/../scripts/helper.sh.tpl", {
    generated_at  = timestamp()
    out_dir       = abspath("${local.out_dir}")
    scripts_dir   = abspath("${path.module}/../scripts") # Note: Adjusted path to your scripts folder
    master_name   = local.master_name
    worker1_name  = local.worker1_name
    worker2_name  = local.worker2_name
    master_memory = var.master_memory
    master_cpus   = var.master_cpus
    worker_memory = var.worker_memory
    worker_cpus   = var.worker_cpus
    disk_size     = var.disk_size
  })
}
resource "multipass_instance" "master" {
  name   = "k8s-master"
  image  = local.image_to_use
  cpus   = var.master_cpus
  memory = var.master_memory
  disk   = var.disk_size
}
resource "multipass_instance" "workers" {
  count  = var.worker_count
  name   = "k8s-worker-${count.index + 1}"
  image  = local.image_to_use
  cpus   = var.worker_cpus
  memory = var.worker_memory
  disk   = var.disk_size
}
resource "local_file" "master_ip" {
  content  = multipass_instance.master.ipv4
  filename = "${path.module}/out/master-ip.txt"
}
resource "null_resource" "setup_common_master" {
  depends_on = [local_file.master_ip]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "bash ../scripts/install-k8s-common.sh ${multipass_instance.master.name} ${var.k8s_version}"
  }
}
# This initializes the Master
resource "null_resource" "init_master" {
  depends_on = [null_resource.setup_common_master]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "bash ../scripts/init-master.sh ${multipass_instance.master.name} ${var.pod_network_cidr} ${var.service_cidr} ${path.cwd}"
  }
}
resource "null_resource" "setup_kubeconfig" {
  depends_on = [null_resource.init_master]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "bash ../scripts/setup-kubeconfig.sh ${multipass_instance.master.name}"
  }
}
resource "null_resource" "setup_common_workers" {
  depends_on = [null_resource.setup_kubeconfig]
  count    = var.worker_count
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "bash ../scripts/install-k8s-common.sh ${multipass_instance.workers[count.index].name} ${var.k8s_version}"
  }
}
