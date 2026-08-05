variable "namespace" {
  description = "Namespace para instalar o ArgoCD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Versao do Helm chart do ArgoCD"
  type        = string
}

variable "applications" {
  description = "Lista de aplicacoes para o ArgoCD monitorar"
  type = list(object({
    name       = string
    repo_url   = string
    path       = string
    namespace  = string
    branch     = string
  }))
}
