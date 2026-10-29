output "ingress_nginx_namespace" {
  description = "Namespace do Ingress Controller"
  value       = module.ingress_nginx.namespace
}

output "metrics_server_namespace" {
  description = "Namespace do Metrics Server"
  value       = module.metrics_server.namespace
}

output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = module.argocd.namespace
}

output "observability_namespace" {
  description = "Namespace da stack de observabilidade"
  value       = module.observability.namespace
}

output "prometheus_endpoint" {
  description = "Endpoint interno do Prometheus"
  value       = module.observability.prometheus_endpoint
}

output "loki_endpoint" {
  description = "Endpoint interno do Loki"
  value       = module.observability.loki_endpoint
}

output "alertmanager_endpoint" {
  description = "Endpoint interno do Alertmanager"
  value       = module.observability.alertmanager_endpoint
}
