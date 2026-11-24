terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6.0"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = var.kubeconfig_path

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 30820 # HashiCorp Vault UI
        host_port      = 8200
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30080 # Redpanda Console UI
        host_port      = 8080
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30081 # Headlamp K8s UI
        host_port      = 8081
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30300 # Grafana UI
        host_port      = 3000
        protocol       = "TCP"
      }
    }

    node {
      role = "worker"
    }
  }
}
