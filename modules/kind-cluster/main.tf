terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
  }
}

resource "kind_cluster" "default" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.cwd}/kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    node {
      role = "worker"

      extra_port_mappings {
        container_port = 30820
        host_port      = 8200
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30080
        host_port      = 8080
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30081
        host_port      = 8081
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30300
        host_port      = 3000
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30900
        host_port      = 9000
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30901
        host_port      = 9001
        protocol       = "TCP"
      }
    }
  }
}
