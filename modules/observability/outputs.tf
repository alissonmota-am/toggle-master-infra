output "namespace" {
  description = "Namespace da stack de observabilidade"
  value       = kubernetes_namespace.observability.metadata[0].name
}

output "prometheus_endpoint" {
  description = "Endpoint interno do Prometheus"
  value       = "http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090"
}

output "loki_endpoint" {
  description = "Endpoint interno do Loki"
  value       = "http://loki-stack.observability.svc.cluster.local:3100"
}

output "alertmanager_endpoint" {
  description = "Endpoint interno do Alertmanager"
  value       = "http://kube-prometheus-stack-alertmanager.observability.svc.cluster.local:9093"
}
