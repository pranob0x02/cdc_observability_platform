output "streaming_namespace" {
  value = kubernetes_namespace.streaming.id
}

output "cdc_topic" {
  value = "cdc.public.orders"
}
