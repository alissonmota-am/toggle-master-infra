variable "chart_version" {
  description = "Versao do Helm chart do Nginx Ingress Controller"
  type        = string
}

variable "lb_allowed_cidrs" {
  description = "CIDRs autorizados a acessar o load balancer (loadBalancerSourceRanges). Nunca deixar vazio: lista vazia libera para 0.0.0.0/0"
  type        = list(string)

  validation {
    condition     = length(var.lb_allowed_cidrs) > 0 && !contains(var.lb_allowed_cidrs, "0.0.0.0/0")
    error_message = "lb_allowed_cidrs nao pode ser vazio nem conter 0.0.0.0/0."
  }
}
