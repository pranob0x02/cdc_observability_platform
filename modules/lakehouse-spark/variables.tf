variable "cluster_secret_store_name" {
  type    = string
  default = "vault-backend"
}

variable "vault_root_token" {
  type    = string
  default = "root"
}

variable "redpanda_namespace" {
  type    = string
  default = "streaming"
}
