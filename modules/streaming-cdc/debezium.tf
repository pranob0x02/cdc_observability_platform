resource "kubernetes_config_map" "debezium_cfg" {
  metadata {
    name      = "debezium-server-config"
    namespace = kubernetes_namespace.streaming.id
  }

  data = {
    "application.properties" = <<-PROPERTIES
      debezium.sink.type=kafka
      debezium.sink.kafka.producer.bootstrap.servers=${local.redpanda_broker_addr}
      debezium.sink.kafka.producer.key.serializer=org.apache.kafka.common.serialization.StringSerializer
      debezium.sink.kafka.producer.value.serializer=org.apache.kafka.common.serialization.StringSerializer

      debezium.source.connector.class=io.debezium.connector.postgresql.PostgresConnector
      debezium.source.plugin.name=pgoutput
      debezium.source.database.hostname=${local.postgres_host_addr}
      debezium.source.database.port=5432
      debezium.source.database.dbname=trading
      debezium.source.topic.prefix=cdc
      debezium.source.schema.include.list=public
      debezium.source.table.include.list=public.orders
      debezium.source.slot.name=debezium_orders_cdc

      debezium.source.bootstrap.servers=${local.redpanda_broker_addr}
      debezium.source.offset.storage=org.apache.kafka.connect.storage.KafkaOffsetBackingStore
      debezium.source.offset.storage.topic=debezium.offsets
      debezium.source.offset.storage.partitions=1
      debezium.source.offset.storage.replication.factor=1
      debezium.source.offset.flush.interval.ms=1000

      quarkus.http.port=8080
    PROPERTIES
  }
}

resource "kubernetes_deployment" "debezium_server" {
  metadata {
    name      = "debezium-server"
    namespace = kubernetes_namespace.streaming.id
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "debezium-server" }
    }

    template {
      metadata {
        labels = { app = "debezium-server" }
        annotations = {
          "config-hash" = sha256(kubernetes_config_map.debezium_cfg.data["application.properties"])
        }
      }

      spec {
        container {
          name  = "debezium"
          image = "quay.io/debezium/server:2.7"

          env {
            name = "DEBEZIUM_SOURCE_DATABASE_USER"
            value_from {
              secret_key_ref {
                name = "postgres-credentials"
                key  = "POSTGRES_USER"
              }
            }
          }
          env {
            name = "DEBEZIUM_SOURCE_DATABASE_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-credentials"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          port {
            name           = "metrics"
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/debezium/config"
          }
        }

        volume {
          name = "config"
          config_map {
            name = "debezium-server-config"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.postgres,
    kubernetes_job.create_cdc_topic
  ]
}

resource "kubernetes_service" "debezium_server" {
  metadata {
    name      = "debezium-server"
    namespace = kubernetes_namespace.streaming.id
    labels    = { app = "debezium-server" }
  }

  spec {
    selector = { app = "debezium-server" }
    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
    }
  }
}
