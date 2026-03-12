variable "master_memory" {
  description = "Memory allocation for master node"
  type        = string
  default     = "2G"
}
variable "master_cpus" {
  description = "CPU allocation for master node"
  type        = number
  default     = 2
}
variable "worker_memory" {
  description = "Memory allocation for worker nodes"
  type        = string
  default     = "1G"
}
variable "worker_cpus" {
  description = "CPU allocation for worker nodes"
  type        = number
  default     = 1
}
variable "disk_size" {
  description = "Disk size for all nodes"
  type        = string
  default     = "20G"
}
variable "k8s_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.28.0-1.1"
}
variable "pod_network_cidr" {
  description = "Pod network CIDR"
  type        = string
  default     = "10.244.0.0/16"
}
variable "service_cidr" {
  description = "Service network CIDR"
  type        = string
  default     = "10.96.0.0/12"
}
