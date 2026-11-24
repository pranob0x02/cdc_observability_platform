resource "kubernetes_config_map" "cdc_grafana_dashboard" {
  metadata {
    name      = "cdc-pipeline-dashboard"
    namespace = kubernetes_namespace.observability.id
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "cdc-pipeline-dashboard.json" = jsonencode({
      title         = "CDC Pipeline & SRE Observability (Postgres -> Debezium -> Redpanda)"
      uid           = "cdc-pipeline-sre"
      tags          = ["cdc", "debezium", "redpanda", "sre"]
      timezone      = "browser"
      schemaVersion = 39
      refresh       = "5s"
      time = {
        from = "now-15m"
        to   = "now"
      }
      panels = [
        {
          id         = 1
          type       = "stat"
          title      = "Debezium CDC Replicas"
          gridPos    = { x = 0, y = 0, w = 6, h = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "max(kube_deployment_status_replicas_available{namespace=\"streaming\", deployment=\"debezium-server\"})"
              legendFormat = "Available"
            }
          ]
          fieldConfig = {
            defaults = {
              mappings = [
                {
                  type = "value"
                  options = {
                    "0" = { text = "DOWN (0)", color = "red" }
                    "1" = { text = "UP (1/1)", color = "green" }
                  }
                }
              ]
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "red", value = null },
                  { color = "green", value = 1 }
                ]
              }
            }
          }
        },
        {
          id         = 2
          type       = "stat"
          title      = "Live CDC Rate (cdc.public.orders)"
          gridPos    = { x = 6, y = 0, w = 6, h = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "sum(rate(redpanda_kafka_records_produced_total{redpanda_topic=\"cdc.public.orders\"}[1m]))"
              legendFormat = "Events/sec"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "ops"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "orange", value = null },
                  { color = "green", value = 0.1 }
                ]
              }
            }
          }
        },
        {
          id         = 3
          type       = "stat"
          title      = "Total CDC Events Delivered"
          gridPos    = { x = 12, y = 0, w = 6, h = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "sum(redpanda_kafka_records_produced_total{redpanda_topic=\"cdc.public.orders\"})"
              legendFormat = "Total Events"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "short"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "blue", value = null }
                ]
              }
            }
          }
        },
        {
          id         = 4
          type       = "stat"
          title      = "Debezium Offsets Committed"
          gridPos    = { x = 18, y = 0, w = 6, h = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "sum(redpanda_kafka_records_produced_total{redpanda_topic=\"debezium.offsets\"})"
              legendFormat = "Offsets"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "short"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "purple", value = null }
                ]
              }
            }
          }
        },
        {
          id         = 5
          type       = "timeseries"
          title      = "Real-Time CDC Throughput (cdc.public.orders events/sec)"
          gridPos    = { x = 0, y = 4, w = 14, h = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "sum(rate(redpanda_kafka_records_produced_total{redpanda_topic=\"cdc.public.orders\"}[1m]))"
              legendFormat = "cdc.public.orders (events/sec)"
            },
            {
              expr         = "sum(rate(redpanda_kafka_records_produced_total{redpanda_topic=\"debezium.offsets\"}[1m]))"
              legendFormat = "debezium.offsets (commits/sec)"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "ops"
              custom = {
                fillOpacity = 20
                lineWidth   = 2
              }
            }
          }
        },
        {
          id         = 6
          type       = "timeseries"
          title      = "Streaming Pods Memory Usage (MB)"
          gridPos    = { x = 14, y = 4, w = 10, h = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "sum by (pod) (container_memory_working_set_bytes{namespace=\"streaming\", container!=\"\"}) / 1024 / 1024"
              legendFormat = "{{pod}}"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "decmbytes"
              custom = {
                fillOpacity = 15
                lineWidth   = 2
              }
            }
          }
        },
        {
          id         = 7
          type       = "logs"
          title      = "Debezium Server Live Logs (Loki)"
          gridPos    = { x = 0, y = 12, w = 24, h = 7 }
          datasource = { type = "loki", uid = "loki" }
          targets = [
            {
              expr = "{namespace=\"streaming\", app=\"debezium-server\"}"
            }
          ]
        }
      ]
    })
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
