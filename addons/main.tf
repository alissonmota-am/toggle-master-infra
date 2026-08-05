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

################################################################################
# External Secrets Operator
################################################################################
module "external_secrets" {
  source = "../modules/external_secrets"

  chart_version = var.external_secrets_chart_version
  aws_region    = var.aws_region
}
