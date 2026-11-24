variable "vault_root_token" {
  type        = string
  description = "Root token for local Vault dev server"
  default     = "root"
}

variable "postgres_db" {
  type    = string
  default = "trading"
}

variable "postgres_user" {
  type    = string
  default = "postgres"
}
