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
