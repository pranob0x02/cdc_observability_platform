output "lakehouse_namespace" {
  value = kubernetes_namespace.lakehouse.id
}

output "minio_endpoint" {
  value = local.minio_internal_url
}
