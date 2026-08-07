################################################################################
# External Secrets Operator via Helm
################################################################################
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version
  namespace  = "external-secrets"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
