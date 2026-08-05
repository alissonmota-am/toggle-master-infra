################################################################################
# Metrics Server via Helm
################################################################################
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.chart_version
  namespace  = "kube-system"
}
