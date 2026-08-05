output "namespace" {
  description = "Namespace onde o ArgoCD foi instalado"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
