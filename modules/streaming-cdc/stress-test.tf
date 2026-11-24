resource "kubernetes_config_map" "pgbench_script" {
  metadata {
    name      = "pgbench-cdc-workload"
    namespace = kubernetes_namespace.streaming.id
  }

  data = {
    "orders_workload.sql" = <<-SQL
      \set symbol_idx random(1, 4)
      \set side_idx random(1, 2)
      \set qty random(1000, 500000)
      \set delta random(-50, 50)

      WITH new_order AS (
        INSERT INTO public.orders (symbol, side, price, quantity, status)
        VALUES (
          CASE :symbol_idx
            WHEN 1 THEN 'EURUSD'
            WHEN 2 THEN 'GBPUSD'
            WHEN 3 THEN 'BTCUSD'
            ELSE 'XAUUSD'
          END,
          CASE :side_idx WHEN 1 THEN 'BUY' ELSE 'SELL' END,
          1.08500 + (:delta * 0.0001),
          :qty,
          'NEW'
        )
        RETURNING order_id
      )
      UPDATE public.orders
      SET status = 'FILLED', updated_at = NOW()
      WHERE order_id = (SELECT order_id FROM new_order);
    SQL
  }
}

resource "kubernetes_job" "pgbench_stress" {
  metadata {
    name      = "pgbench-cdc-stress"
    namespace = kubernetes_namespace.streaming.id
  }

  wait_for_completion = false

  spec {
    backoff_limit = 2
    template {
      metadata {
        labels = { app = "pgbench-stress" }
      }
      spec {
        restart_policy = "Never"
        container {
          name  = "pgbench"
          image = "postgres:16-alpine"
          command = [
            "pgbench",
            "-h", "postgres.streaming.svc.cluster.local",
            "-U", "postgres",
            "-d", "trading",
            "-n",
            "-c", "2",
            "-j", "2",
            "-R", tostring(var.stress_tps),
            "-T", tostring(var.stress_duration_seconds),
            "-f", "/scripts/orders_workload.sql"
          ]
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-credentials"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          volume_mount {
            name       = "workload"
            mount_path = "/scripts"
          }
        }
        volume {
          name = "workload"
          config_map {
            name = kubernetes_config_map.pgbench_script.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.debezium_server]
}
