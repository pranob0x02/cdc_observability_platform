include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/observability-uis"
}

dependency "cluster" {
  config_path = "../01-cluster"

  mock_outputs = {
    kubeconfig_path = "/tmp/mock-kubeconfig"
  }
}

dependency "security" {
  config_path = "../02-security"

  mock_outputs = {
    cluster_secret_store_name = "vault-backend"
    grafana_secret_path       = "observability/grafana"
  }
}

dependency "streaming" {
  config_path = "../03-streaming"

  mock_outputs = {
    streaming_namespace = "streaming"
  }
}

inputs = {
  kubeconfig_path           = dependency.cluster.outputs.kubeconfig_path
  cluster_secret_store_name = dependency.security.outputs.cluster_secret_store_name
  grafana_secret_path       = dependency.security.outputs.grafana_secret_path
  streaming_namespace       = dependency.streaming.outputs.streaming_namespace
  vault_root_token          = "root"
}
