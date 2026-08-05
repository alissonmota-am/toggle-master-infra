output "namespace" {
  description = "Namespace do Ingress Controller"
  value       = helm_release.ingress_nginx.namespace
}
