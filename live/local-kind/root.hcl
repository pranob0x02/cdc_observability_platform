remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

generate "k8s_providers" {
  path      = "generated_providers.tf"
  if_exists = "overwrite_terragrunt"
  disable   = basename(get_terragrunt_dir()) == "01-cluster"
  contents  = <<-EOF
    variable "kubeconfig_path" {
      type    = string
      default = ""
    }

    provider "kubernetes" {
      config_path = var.kubeconfig_path
    }

    provider "helm" {
      kubernetes {
        config_path = var.kubeconfig_path
      }
    }

    provider "kubectl" {
      config_path      = var.kubeconfig_path
      load_config_file = true
    }
  EOF
}
