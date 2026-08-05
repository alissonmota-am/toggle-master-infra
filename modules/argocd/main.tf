################################################################################
# Namespace
################################################################################
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

################################################################################
# ArgoCD via Helm
################################################################################
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
}

################################################################################
# ArgoCD Applications via Helm (chart argocd-apps)
################################################################################
resource "helm_release" "applications" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"
  namespace  = var.namespace

  values = [yamlencode({
    applications = { for app in var.applications : app.name => {
      project = "default"
      source = {
        repoURL        = app.repo_url
        targetRevision = app.branch
        path           = app.path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = app.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }}
  })]

  depends_on = [helm_release.argocd]
}
