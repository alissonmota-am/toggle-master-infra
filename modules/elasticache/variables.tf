variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "subnet_ids" {
  description = "IDs das subnets privadas para o ElastiCache"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security Group ID dos nodes do EKS (source para ingress)"
  type        = string
}

variable "node_type" {
  description = "Tipo do node do ElastiCache"
  type        = string
}
