variable "cluster_name" {
  type        = string
  description = "Name of the local kind Kubernetes cluster"
  default     = "cdc-observability-lab"
}

variable "kubeconfig_path" {
  type        = string
  description = "Destination path to write the generated kubeconfig"
}
