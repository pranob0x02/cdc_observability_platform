resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "vault_kv_secret_v2" "postgres" {
  mount      = "secret"
  name       = "trading/postgres"
  depends_on = [time_sleep.wait_for_vault]

  data_json = jsonencode({
    username = var.postgres_user
    password = random_password.postgres.result
    database = var.postgres_db
  })
}

resource "vault_kv_secret_v2" "grafana" {
  mount      = "secret"
  name       = "observability/grafana"
  depends_on = [time_sleep.wait_for_vault]

  data_json = jsonencode({
    admin-user     = "admin"
    admin-password = random_password.grafana.result
  })
}
