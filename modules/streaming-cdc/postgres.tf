terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

resource "kubernetes_namespace" "streaming" {
  metadata {
    name = "streaming"
  }
}

resource "kubectl_manifest" "postgres_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: postgres-credentials
      namespace: ${kubernetes_namespace.streaming.id}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.cluster_secret_store_name}
        kind: ClusterSecretStore
      target:
        name: postgres-credentials
        creationPolicy: Owner
      data:
        - secretKey: POSTGRES_USER
          remoteRef:
            key: ${var.postgres_secret_path}
            property: username
        - secretKey: POSTGRES_PASSWORD
          remoteRef:
            key: ${var.postgres_secret_path}
            property: password
        - secretKey: POSTGRES_DB
          remoteRef:
            key: ${var.postgres_secret_path}
            property: database
  YAML
}

resource "time_sleep" "wait_for_pg_secret" {
  depends_on      = [kubectl_manifest.postgres_external_secret]
  create_duration = "5s"
}

resource "kubernetes_config_map" "postgres_init" {
  metadata {
    name      = "postgres-init-sql"
    namespace = kubernetes_namespace.streaming.id
  }

  data = {
    "init.sql" = <<-SQL
      CREATE TABLE IF NOT EXISTS public.orders (
        order_id SERIAL PRIMARY KEY,
        symbol VARCHAR(16) NOT NULL,
        side VARCHAR(4) NOT NULL,
        price NUMERIC(12, 5) NOT NULL,
        quantity NUMERIC(12, 2) NOT NULL,
        status VARCHAR(16) DEFAULT 'NEW',
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      ALTER TABLE public.orders REPLICA IDENTITY FULL;

      INSERT INTO public.orders (symbol, side, price, quantity, status)
      VALUES
        ('EURUSD', 'BUY', 1.08450, 100000, 'FILLED'),
        ('BTCUSD', 'SELL', 92450.00, 1.5, 'NEW');
    SQL
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.streaming.id
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "postgres" }
    }

    template {
      metadata {
        labels = { app = "postgres" }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          args = [
            "-c", "wal_level=logical",
            "-c", "max_wal_senders=4",
            "-c", "max_replication_slots=4"
          ]

          env_from {
            secret_ref {
              name = "postgres-credentials"
            }
          }

          port {
            container_port = 5432
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-d", "trading"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          volume_mount {
            name       = "init-sql"
            mount_path = "/docker-entrypoint-initdb.d"
          }
        }

        volume {
          name = "init-sql"
          config_map {
            name = kubernetes_config_map.postgres_init.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_pg_secret]
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.streaming.id
  }

  spec {
    selector = { app = "postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}
