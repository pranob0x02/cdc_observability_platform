locals {
  monitoring_api_version = join(".", ["monitoring", "coreos", "com/v1"])
}

resource "kubectl_manifest" "redpanda_service_monitor" {
  yaml_body = <<-YAML
    apiVersion: ${local.monitoring_api_version}
    kind: ServiceMonitor
    metadata:
      name: redpanda-cdc-monitor
      namespace: ${kubernetes_namespace.observability.id}
    spec:
      namespaceSelector:
        matchNames:
          - ${var.streaming_namespace}
      selector:
        matchLabels:
          app.kubernetes.io/name: redpanda
      endpoints:
        - port: admin
          path: /public_metrics
          interval: 5s
  YAML

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "cdc_slo_burn_rate" {
  yaml_body = <<-YAML
    apiVersion: ${local.monitoring_api_version}
    kind: PrometheusRule
    metadata:
      name: cdc-pipeline-slo-alerts
      namespace: ${kubernetes_namespace.observability.id}
    spec:
      groups:
        - name: cdc-slo-burn-rate
          rules:
            - alert: CDCConnectorDown
              expr: kube_deployment_status_replicas_available{namespace="${var.streaming_namespace}", deployment="debezium-server"} == 0
              for: 30s
              labels:
                severity: critical
                slo: 99.5-percent-cdc-availability
              annotations:
                summary: "Debezium CDC pod is down — PostgreSQL WAL replication paused"
                description: "Debezium Server has 0 available replicas for 30s. PostgreSQL replication slot is retaining WAL changes."

            - alert: CDCPipelineHighErrorBudgetBurn
              expr: |
                (
                  sum(rate(redpanda_kafka_records_produced_total{redpanda_topic="cdc.public.orders"}[5m])) == 0
                  and
                  sum(rate(kube_pod_container_status_restarts_total{namespace="${var.streaming_namespace}"}[15m])) > 0
                )
              for: 1m
              labels:
                severity: critical
                slo: 99.5-percent-cdc-delivery
              annotations:
                summary: "Fast SLO Error Budget Burn on CDC Pipeline"
                description: "Zero CDC events written to cdc.public.orders over 5m alongside container restarts in streaming namespace."
  YAML

  depends_on = [helm_release.kube_prometheus_stack]
}
