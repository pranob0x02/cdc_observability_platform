terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = var.vault_root_token
}

locals {
  minio_internal_url = format("%s://%s.%s.svc.cluster.local:%s", "http", "minio", "lakehouse", "9000")
}

resource "kubernetes_namespace" "lakehouse" {
  metadata {
    name = "lakehouse"
  }
}

# 1. Generate MinIO root secret key & store in Vault KV-v2
resource "random_password" "minio_secret_key" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "minio" {
  mount = "secret"
  name  = "lakehouse/minio"

  data_json = jsonencode({
    MINIO_ROOT_USER     = "lakehouse-admin"
    MINIO_ROOT_PASSWORD = random_password.minio_secret_key.result
    endpoint            = local.minio_internal_url
  })
}

# 2. Sync Vault secret into Kubernetes via External Secrets Operator
resource "kubectl_manifest" "minio_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: minio-credentials
      namespace: ${kubernetes_namespace.lakehouse.id}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.cluster_secret_store_name}
        kind: ClusterSecretStore
      target:
        name: minio-credentials
        creationPolicy: Owner
      data:
        - secretKey: MINIO_ROOT_USER
          remoteRef:
            key: lakehouse/minio
            property: MINIO_ROOT_USER
        - secretKey: MINIO_ROOT_PASSWORD
          remoteRef:
            key: lakehouse/minio
            property: MINIO_ROOT_PASSWORD
  YAML

  depends_on = [vault_kv_secret_v2.minio]
}

resource "time_sleep" "wait_for_minio_secret" {
  depends_on      = [kubectl_manifest.minio_external_secret]
  create_duration = "5s"
}

# 3. Deploy MinIO Server (S3 API :9000 + Console UI :9001)
resource "kubernetes_deployment" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.lakehouse.id
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "minio" }
    }

    template {
      metadata {
        labels = { app = "minio" }
      }

      spec {
        container {
          name  = "minio"
          image = "cgr.dev/chainguard/minio:latest"
          args  = ["server", "/data", "--console-address", ":9001"]

          env_from {
            secret_ref {
              name = "minio-credentials"
            }
          }

          port {
            name           = "s3-api"
            container_port = 9000
          }
          port {
            name           = "console"
            container_port = 9001
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = 9000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          volume_mount {
            name       = "storage"
            mount_path = "/data"
          }
        }

        volume {
          name = "storage"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_minio_secret]
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.lakehouse.id
  }

  spec {
    type     = "NodePort"
    selector = { app = "minio" }

    port {
      name        = "s3-api"
      port        = 9000
      target_port = 9000
      node_port   = 30900
    }
    port {
      name        = "console"
      port        = 9001
      target_port = 9001
      node_port   = 30901
    }
  }
}

# 4. Initialize 'warehouse' (Iceberg) and 'checkpoints' (Spark) buckets
resource "kubernetes_job" "create_minio_buckets" {
  metadata {
    name      = "create-minio-buckets"
    namespace = kubernetes_namespace.lakehouse.id
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "mc"
          image = "cgr.dev/chainguard/minio-client:latest-dev"
          command = [
            "/bin/sh", "-c",
            "until mc alias set lakehouse ${local.minio_internal_url} \"$MINIO_ROOT_USER\" \"$MINIO_ROOT_PASSWORD\"; do sleep 2; done && mc mb --ignore-existing lakehouse/warehouse && mc mb --ignore-existing lakehouse/checkpoints"
          ]

          env_from {
            secret_ref {
              name = "minio-credentials"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.minio, kubernetes_service.minio]
}
