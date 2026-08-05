variable "chart_version" {
  description = "Versao do Helm chart do External Secrets Operator"
  type        = string
}

variable "aws_region" {
  description = "Regiao AWS para o Secrets Manager"
  type        = string
}
