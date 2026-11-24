resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.security.id
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      installCRDs = true
      resources = {
        requests = { memory = "64Mi", cpu = "50m" }
        limits   = { memory = "192Mi", cpu = "300m" }
      }
    })
  ]

  depends_on = [helm_release.vault]
}

resource "kubectl_manifest" "vault_cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: vault-backend
    spec:
      provider:
        vault:
          server: ${join("", ["http://", "vault", ".", "security", ".svc.cluster.local:", "8200"])}
          path: secret
          version: v2
          auth:
            kubernetes:
              mountPath: kubernetes
              role: external-secrets
              serviceAccountRef:
                name: external-secrets
                namespace: security
                audiences:
                  - ${join("", ["https://", "kubernetes", ".default", ".svc.cluster.local"])}
  YAML

  depends_on = [
    helm_release.external_secrets,
    vault_kubernetes_auth_backend_role.eso
  ]
}
