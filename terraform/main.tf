terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4.2"
    }
  }
}
locals {
  # Logic: Use local file if provided, otherwise standard Ubuntu 24.04
  image_to_use = var.k8s_golden_image != "" ? "file://${abspath(var.k8s_golden_image)}" : "24.04"
}
# 1. Create the Master VM
resource "multipass_instance" "master" {
  name   = "k8s-master"
  image  = local.image_to_use
  cpus   = var.master_cpus
  memory = var.master_memory
  disk   = var.disk_size
}
# 2. Create the Worker VMs
resource "multipass_instance" "workers" {
  count  = var.worker_count
  name   = "k8s-worker-${count.index + 1}"
  image  = local.image_to_use
  cpus   = var.worker_cpus
  memory = var.worker_memory
  disk   = var.disk_size
}
# 3. BRIDGE: Export IPs to files for your existing Bash scripts
resource "local_file" "master_ip" {
  content  = multipass_instance.master.ipv4
  filename = "${path.module}/../out/master-ip.txt"
}
# 4. EXECUTION: Run your existing Bash scripts
# This runs the "common" setup on the Master
resource "null_resource" "setup_common_master" {
  triggers = { instance_id = multipass_instance.master.id }
  provisioner "local-exec" {
    command = "bash ../scripts/install-k8s-common.sh ${multipass_instance.master.name} ${var.k8s_version}"
  }
}
# This initializes the Master
resource "null_resource" "init_master" {
  depends_on = [null_resource.setup_common_master, local_file.master_ip]
  
  provisioner "local-exec" {
    command = "bash ../scripts/init-master.sh ${multipass_instance.master.name} ${multipass_instance.master.ipv4} ${var.pod_network_cidr}"
  }
}
# This runs the "common" setup on Workers in parallel
resource "null_resource" "setup_common_workers" {
  count    = var.worker_count
  triggers = { instance_id = multipass_instance.workers[count.index].id }
  provisioner "local-exec" {
    command = "bash ../scripts/install-k8s-common.sh ${multipass_instance.workers[count.index].name} ${var.k8s_version}"
  }
}
