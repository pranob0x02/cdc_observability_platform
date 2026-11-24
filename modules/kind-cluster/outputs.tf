output "kubeconfig_path" {
  value       = kind_cluster.this.kubeconfig_path
  description = "Absolute path to the kind cluster kubeconfig"
}

output "cluster_name" {
  value = kind_cluster.this.name
}
