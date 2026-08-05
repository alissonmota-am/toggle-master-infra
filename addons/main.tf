################################################################################
# Ingress Nginx Controller
################################################################################
module "ingress_nginx" {
  source = "../modules/ingress_nginx"

  chart_version = var.ingress_nginx_chart_version
}

################################################################################
# Metrics Server
################################################################################
module "metrics_server" {
  source = "../modules/metrics_server"

  chart_version = var.metrics_server_chart_version
}

################################################################################
# ArgoCD
################################################################################
module "argocd" {
  source = "../modules/argocd"

  chart_version = var.argocd_chart_version
  applications  = var.argocd_applications
}
