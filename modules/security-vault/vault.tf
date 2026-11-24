terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

resource "kubernetes_namespace" "security" {
  metadata {
    name = "security"
  }
}

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = kubernetes_namespace.security.id
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      global = {
        enabled = true
      }
      injector = {
        enabled = false
      }
      server = {
        dev = {
          enabled      = true
          devRootToken = var.vault_root_token
        }
        service = {
          type     = "NodePort"
          nodePort = 30820
        }
        resources = {
          requests = { memory = "128Mi", cpu = "100m" }
          limits   = { memory = "256Mi", cpu = "500m" }
        }
      }
      ui = {
        enabled     = true
        serviceType = "NodePort"
      }
    })
  ]
}

resource "time_sleep" "wait_for_vault" {
  depends_on      = [helm_release.vault]
  create_duration = "10s"
}

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = var.vault_root_token
}

data "kubernetes_config_map" "kube_root_ca" {
  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

resource "vault_auth_backend" "kubernetes" {
  type       = "kubernetes"
  depends_on = [time_sleep.wait_for_vault]
}

resource "vault_kubernetes_auth_backend_config" "k8s" {
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = join("", ["https://", "kubernetes", ".default", ".svc.cluster.local:", "443"])
  kubernetes_ca_cert     = data.kubernetes_config_map.kube_root_ca.data["ca.crt"]
  disable_iss_validation = true
}

resource "vault_policy" "eso_read" {
  name       = "eso-read-policy"
  depends_on = [time_sleep.wait_for_vault]

  policy = <<-HCL
    path "secret/data/*" {
      capabilities = ["read"]
    }
  HCL
}

resource "vault_kubernetes_auth_backend_role" "eso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = [kubernetes_namespace.security.id]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.eso_read.name]
}
