variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "subnet_ids" {
  description = "IDs das subnets para o cluster e nodes (privadas)"
  type        = list(string)
}

variable "cluster_version" {
  description = "Versao do Kubernetes"
  type        = string
}

variable "role_arn" {
  description = "ARN da IAM Role para o cluster e nodes"
  type        = string
}

variable "node_instance_type" {
  description = "Tipo de instancia dos nodes"
  type        = string
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
}

variable "node_min_size" {
  description = "Quantidade minima de nodes"
  type        = number
}

variable "node_max_size" {
  description = "Quantidade maxima de nodes"
  type        = number
}

variable "node_capacity_type" {
  description = "Tipo de capacidade (ON_DEMAND ou SPOT)"
  type        = string
}
