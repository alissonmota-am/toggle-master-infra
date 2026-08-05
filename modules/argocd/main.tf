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
# ArgoCD Applications
################################################################################
resource "kubernetes_manifest" "applications" {
  for_each = { for app in var.applications : app.name => app }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.value.name
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = each.value.repo_url
        targetRevision = each.value.branch
        path           = each.value.path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = each.value.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
