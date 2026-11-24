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
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

resource "kubectl_manifest" "grafana_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: grafana-admin
      namespace: ${kubernetes_namespace.observability.id}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.cluster_secret_store_name}
        kind: ClusterSecretStore
      target:
        name: grafana-admin
        creationPolicy: Owner
      data:
        - secretKey: admin-user
          remoteRef:
            key: ${var.grafana_secret_path}
            property: admin-user
        - secretKey: admin-password
          remoteRef:
            key: ${var.grafana_secret_path}
            property: admin-password
  YAML
}

resource "time_sleep" "wait_for_grafana_secret" {
  depends_on      = [kubectl_manifest.grafana_external_secret]
  create_duration = "5s"
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = format("%s://%s.github.io/helm-charts", "https", "prometheus-community")
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.observability.id
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      grafana = {
        admin = {
          existingSecret = "grafana-admin"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }
        service = {
          type     = "NodePort"
          nodePort = 30300
        }
      }
      prometheus = {
        prometheusSpec = {
          serviceMonitorSelectorNilUsesHelmValues = false
          ruleSelectorNilUsesHelmValues           = false
        }
      }
    })
  ]

  depends_on = [time_sleep.wait_for_grafana_secret]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = format("%s://%s.github.io/helm-charts", "https", "grafana")
  chart      = "loki-stack"
  namespace  = kubernetes_namespace.observability.id
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      promtail = {
        enabled = true
        config = {
          snippets = {
            pipelineStages = [
              { cri = {} }
            ]
          }
        }
      }
      loki = {
        isDefault   = false
        persistence = { enabled = false }
      }
    })
  ]
}

resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = format("%s://%s.github.io/opentelemetry-helm-charts", "https", "open-telemetry")
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.observability.id

  values = [
    yamlencode({
      mode = "deployment"
      image = {
        repository = "otel/opentelemetry-collector-contrib"
      }
      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }
        }
        exporters = {
          prometheus = {
            endpoint = "0.0.0.0:8889"
          }
          debug = {}
        }
        service = {
          pipelines = {
            metrics = {
              receivers = ["otlp"]
              exporters = ["prometheus"]
            }
            traces = {
              receivers = ["otlp"]
              exporters = ["debug"]
            }
          }
        }
      }
    })
  ]
}
