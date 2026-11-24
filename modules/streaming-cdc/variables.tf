variable "cluster_secret_store_name" {
  type    = string
  default = "vault-backend"
}

variable "postgres_secret_path" {
  type    = string
  default = "trading/postgres"
}

variable "stress_tps" {
  type        = number
  description = "Transactions per second for pgbench CDC load generator (each txn = 1 INSERT + 1 UPDATE = 2 CDC events)"
  default     = 10
}

variable "stress_duration_seconds" {
  type        = number
  description = "Duration in seconds for pgbench workload run"
  default     = 600
}
