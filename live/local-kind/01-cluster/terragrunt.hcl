include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/kind-cluster"
}

inputs = {
  cluster_name    = "cdc-observability-lab"
  kubeconfig_path = "${get_terragrunt_dir()}/kubeconfig"
}
