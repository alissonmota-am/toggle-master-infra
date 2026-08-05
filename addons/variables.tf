variable "aws_region" {
  description = "Regiao AWS"
  type        = string
}

# Remote State da plataforma
variable "platform_state_bucket" {
  description = "Bucket S3 onde esta o state da plataforma"
  type        = string
}

variable "platform_state_key" {
  description = "Key do state da plataforma no S3"
  type        = string
}

# Ingress Nginx
variable "ingress_nginx_chart_version" {
  description = "Versao do Helm chart do Nginx Ingress Controller"
  type        = string
}

# Metrics Server
variable "metrics_server_chart_version" {
  description = "Versao do Helm chart do Metrics Server"
  type        = string
}

# ArgoCD
variable "argocd_chart_version" {
  description = "Versao do Helm chart do ArgoCD"
  type        = string
}

variable "argocd_applications" {
  description = "Lista de aplicacoes para o ArgoCD monitorar"
  type = list(object({
    name       = string
    repo_url   = string
    path       = string
    namespace  = string
    branch     = string
  }))
}
