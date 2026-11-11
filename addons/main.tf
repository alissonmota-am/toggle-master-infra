################################################################################
# Ingress Nginx Controller
################################################################################
module "ingress_nginx" {
  source = "../modules/ingress_nginx"

  chart_version    = var.ingress_nginx_chart_version
  lb_allowed_cidrs = var.lb_allowed_cidrs
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

  chart_version    = var.argocd_chart_version
  applications     = var.argocd_applications
  lb_allowed_cidrs = var.lb_allowed_cidrs
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
  self_healing_url                    = module.self_healing.function_url
  self_healing_webhook_token          = var.self_healing_webhook_token
  lb_allowed_cidrs                    = var.lb_allowed_cidrs
}

################################################################################
# Self-Healing (Lambda chamada pelo Alertmanager -> dispara o GitHub Actions)
################################################################################
module "self_healing" {
  source = "../modules/self_healing"

  github_token  = var.self_healing_github_token
  webhook_token = var.self_healing_webhook_token
}
