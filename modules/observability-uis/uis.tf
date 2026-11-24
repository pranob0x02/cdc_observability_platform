provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = var.vault_root_token
}

resource "helm_release" "headlamp" {
  name       = "headlamp"
  repository = format("%s://%s.github.io/headlamp/", "https", "kubernetes-sigs")
  chart      = "headlamp"
  namespace  = "kube-system"
  wait       = true

  values = [
    yamlencode({
      service = {
        type     = "NodePort"
        nodePort = 30081
      }
    })
  ]
}

resource "kubernetes_service_account" "headlamp_admin" {
  metadata {
    name      = "headlamp-platform-admin"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "headlamp_admin" {
  metadata {
    name = "headlamp-platform-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "headlamp-platform-admin"
    namespace = "kube-system"
  }
}

resource "kubernetes_secret" "headlamp_token" {
  metadata {
    name      = "headlamp-platform-admin-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = "headlamp-platform-admin"
    }
  }

  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_cluster_role_binding.headlamp_admin]
}

resource "vault_kv_secret_v2" "headlamp" {
  mount = "secret"
  name  = "platform/headlamp"

  data_json = jsonencode({
    url   = "http://localhost:8081"
    token = kubernetes_secret.headlamp_token.data["token"]
  })
}
