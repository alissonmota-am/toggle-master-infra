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

################################################################################
# Observability Stack (Prometheus + Grafana + Alertmanager + Loki + Promtail + OTel Collector)
################################################################################
module "observability" {
  source = "../modules/observability"

  kube_prometheus_stack_chart_version = var.kube_prometheus_stack_chart_version
  loki_stack_chart_version            = var.loki_stack_chart_version
  grafana_admin_password              = var.grafana_admin_password
  new_relic_license_key               = var.new_relic_license_key
  slack_webhook_url                   = var.slack_webhook_url
  pagerduty_routing_key               = var.pagerduty_routing_key
  environment                         = var.environment
}
