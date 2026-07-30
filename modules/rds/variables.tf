variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "subnet_ids" {
  description = "IDs das subnets privadas para o RDS"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security Group ID dos nodes do EKS (source para ingress)"
  type        = string
}

variable "instance_class" {
  description = "Classe da instancia RDS"
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
}

variable "username" {
  description = "Usuario master do RDS"
  type        = string
}

variable "password" {
  description = "Senha do usuario master"
  type        = string
  sensitive   = true
}
