include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/security-vault"
}

dependency "cluster" {
  config_path = "../01-cluster"

  mock_outputs = {
    kubeconfig_path = "/tmp/mock-kubeconfig"
  }
}

inputs = {
  kubeconfig_path  = dependency.cluster.outputs.kubeconfig_path
  vault_root_token = "root"
  postgres_db      = "trading"
  postgres_user    = "postgres"
}
