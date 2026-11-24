locals {
  redpanda_broker_addr = format("%s.%s.svc.cluster.local:%s", "redpanda", "streaming", "9093")
  postgres_host_addr   = format("%s.%s.svc.cluster.local", "postgres", "streaming")
}

resource "helm_release" "redpanda" {
  name       = "redpanda"
  repository = format("%s://%s.%s.com", "https", "charts", "redpanda")
  chart      = "redpanda"
  namespace  = kubernetes_namespace.streaming.id
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      statefulset = {
        replicas = 1
      }
      resources = {
        cpu = { cores = 1 }
        memory = {
          container = { max = "1.5Gi" }
        }
      }
      storage = {
        persistentVolume = { enabled = false }
      }
      external = {
        enabled = false
      }
      tls  = { enabled = false }
      auth = { sasl = { enabled = false } }
      tuning = {
        tune_aio_events = false
      }
      console = {
        enabled = true
        service = {
          type     = "NodePort"
          nodePort = 30080
        }
      }
    })
  ]
}

resource "kubernetes_job" "create_cdc_topic" {
  metadata {
    name      = "create-cdc-topic"
    namespace = kubernetes_namespace.streaming.id
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "rpk"
          image = "redpandadata/redpanda:latest"
          command = [
            "rpk", "topic", "create", "cdc.public.orders",
            "--brokers", local.redpanda_broker_addr,
            "-p", "3", "-r", "1"
          ]
        }
      }
    }
  }

  depends_on = [helm_release.redpanda]
}
