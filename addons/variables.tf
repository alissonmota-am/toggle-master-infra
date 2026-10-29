variable "aws_region" {
  description = "Regiao AWS"
  type        = string
}

# Remote State da plataforma
variable "platform_state_bucket" {
  description = "Bucket S3 onde esta o state da plataforma"
  type        = string
}

variable "platform_state_key" {
  description = "Key do state da plataforma no S3"
  type        = string
}

# Ingress Nginx
variable "ingress_nginx_chart_version" {
  description = "Versao do Helm chart do Nginx Ingress Controller"
  type        = string
}

# Metrics Server
variable "metrics_server_chart_version" {
  description = "Versao do Helm chart do Metrics Server"
  type        = string
}

# ArgoCD
variable "argocd_chart_version" {
  description = "Versao do Helm chart do ArgoCD"
  type        = string
}

variable "argocd_applications" {
  description = "Lista de aplicacoes para o ArgoCD monitorar"
  type = list(object({
    name       = string
    repo_url   = string
    path       = string
    namespace  = string
    branch     = string
  }))
}

# External Secrets
variable "external_secrets_chart_version" {
  description = "Versao do Helm chart do External Secrets Operator"
  type        = string
}

# Observability
variable "kube_prometheus_stack_chart_version" {
  description = "Versao do Helm chart do kube-prometheus-stack"
  type        = string
}

variable "loki_stack_chart_version" {
  description = "Versao do Helm chart do loki-stack"
  type        = string
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana"
  type        = string
  sensitive   = true
}

variable "new_relic_license_key" {
  description = "License key do New Relic"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Webhook URL do Slack para alertas"
  type        = string
  sensitive   = true
}

variable "pagerduty_routing_key" {
  description = "Integration key do PagerDuty"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Nome do ambiente (dev, prod)"
  type        = string
  default     = "dev"
}
