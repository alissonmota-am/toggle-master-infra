output "namespace" {
  description = "Namespace do External Secrets Operator"
  value       = helm_release.external_secrets.namespace
}
