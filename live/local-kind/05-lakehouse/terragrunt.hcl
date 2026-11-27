include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/lakehouse-spark"
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
  redpanda_namespace        = dependency.streaming.outputs.streaming_namespace
  vault_root_token          = "root"
}
