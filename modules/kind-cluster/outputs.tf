resource "local_file" "kubeconfig" {
  content         = kind_cluster.default.kubeconfig
  filename        = abspath("${path.module}/../../live/local-kind/01-cluster/kubeconfig")
  file_permission = "0600"
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig for the local kind cluster"
  value       = local_file.kubeconfig.filename
}

output "cluster_name" {
  value = kind_cluster.default.name
}
