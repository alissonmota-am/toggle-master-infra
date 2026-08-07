aws_region = "us-east-1"

# Remote State da plataforma
platform_state_bucket = "toggle-master-terraform-state-103568492404"
platform_state_key    = "platform/dev/terraform.tfstate"

# Ingress Nginx
ingress_nginx_chart_version = "4.10.1"

# Metrics Server
metrics_server_chart_version = "3.12.1"

# ArgoCD
argocd_chart_version = "7.3.11"

argocd_applications = [
  {
    name       = "cluster-base"
    repo_url   = "https://github.com/alissonmota-am/toggle-master-infra.git"
    path       = "k8s-base"
    namespace  = "external-secrets"
    branch     = "develop"
  },
  {
    name       = "auth-service"
    repo_url   = "https://github.com/alissonmota-am/auth-service.git"
    path       = "k8s"
    namespace  = "auth-service"
    branch     = "develop"
  },
  {
    name       = "flag-service"
    repo_url   = "https://github.com/alissonmota-am/flag-service.git"
    path       = "k8s"
    namespace  = "flag-service"
    branch     = "develop"
  },
  {
    name       = "targeting-service"
    repo_url   = "https://github.com/alissonmota-am/targeting-service.git"
    path       = "k8s"
    namespace  = "targeting-service"
    branch     = "develop"
  },
  {
    name       = "evaluation-service"
    repo_url   = "https://github.com/alissonmota-am/evaluation-service.git"
    path       = "k8s"
    namespace  = "evaluation-service"
    branch     = "develop"
  },
  {
    name       = "analytics-service"
    repo_url   = "https://github.com/alissonmota-am/analytics-service.git"
    path       = "k8s"
    namespace  = "analytics-service"
    branch     = "develop"
  }
]

# External Secrets
external_secrets_chart_version = "0.9.20"
