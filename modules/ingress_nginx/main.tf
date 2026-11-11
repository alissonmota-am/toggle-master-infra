################################################################################
# Nginx Ingress Controller via Helm
################################################################################
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.chart_version
  namespace  = "ingress-nginx"

  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  # Acesso externo restrito: por padrao so a VPC. O IP do operador e liberado sob
  # demanda por scripts/lb-access.sh (fora do Terraform).
  values = [
    yamlencode({
      controller = {
        service = {
          loadBalancerSourceRanges = var.lb_allowed_cidrs
        }
      }
    })
  ]
}
