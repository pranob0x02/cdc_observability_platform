output "cluster_secret_store_name" {
  value = "vault-backend"
}

output "postgres_secret_path" {
  value = "trading/postgres"
}

output "grafana_secret_path" {
  value = "observability/grafana"
}
