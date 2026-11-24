include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/streaming-cdc"
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
    postgres_secret_path      = "trading/postgres"
  }
}

inputs = {
  kubeconfig_path           = dependency.cluster.outputs.kubeconfig_path
  cluster_secret_store_name = dependency.security.outputs.cluster_secret_store_name
  postgres_secret_path      = dependency.security.outputs.postgres_secret_path
  stress_tps                = 10
  stress_duration_seconds   = 600
}
