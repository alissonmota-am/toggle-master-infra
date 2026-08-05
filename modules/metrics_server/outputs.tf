output "namespace" {
  description = "Namespace do Metrics Server"
  value       = helm_release.metrics_server.namespace
}
