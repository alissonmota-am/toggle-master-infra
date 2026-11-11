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

variable "self_healing_url" {
  description = "URL da Function URL da Lambda de self-healing (destino do webhook do Alertmanager para alertas criticos)"
  type        = string
}

variable "self_healing_webhook_token" {
  description = "Token enviado pelo Alertmanager no cabecalho Authorization da chamada a Lambda"
  type        = string
  sensitive   = true
}

variable "lb_allowed_cidrs" {
  description = "CIDRs autorizados a acessar o load balancer (loadBalancerSourceRanges). Nunca deixar vazio: lista vazia libera para 0.0.0.0/0"
  type        = list(string)

  validation {
    condition     = length(var.lb_allowed_cidrs) > 0 && !contains(var.lb_allowed_cidrs, "0.0.0.0/0")
    error_message = "lb_allowed_cidrs nao pode ser vazio nem conter 0.0.0.0/0."
  }
}
