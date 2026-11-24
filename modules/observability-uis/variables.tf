variable "cluster_secret_store_name" {
  type    = string
  default = "vault-backend"
}

variable "grafana_secret_path" {
  type    = string
  default = "observability/grafana"
}

variable "streaming_namespace" {
  type    = string
  default = "streaming"
}

variable "vault_root_token" {
  type    = string
  default = "root"
}
