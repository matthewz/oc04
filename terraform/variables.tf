variable "k8s_golden_image" {
  type        = string
  default     = "" 
  description = "Path to your local .img file. If empty, uses Ubuntu 24.04"
}
variable "master_cpus" { default = 2 }
variable "master_memory" { default = "4G" }
variable "worker_count" { default = 2 }
variable "worker_cpus" { default = 2 }
variable "worker_memory" { default = "2G" }
variable "disk_size" { default = "20G" }
variable "k8s_version" { default = "1.30.0" }
variable "pod_network_cidr" { default = "10.244.0.0/16" }
variable "service_cidr" {
  default = "10.96.0.0/12"
}
