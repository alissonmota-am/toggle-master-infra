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
  description = "License key do New Relic para o OTel Collector exportar traces e métricas"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Webhook URL do canal Slack para notificações de alerta"
  type        = string
  sensitive   = true
}

variable "pagerduty_routing_key" {
  description = "Integration key do serviço PagerDuty para abertura automática de incidentes"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Nome do ambiente (dev, prod) — injetado nos atributos de recurso do OTel"
  type        = string
  default     = "dev"
}
