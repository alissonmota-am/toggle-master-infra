variable "aws_region" {
  description = "Regiao AWS para deploy dos recursos"
  type        = string
}

variable "project_name" {
  description = "Nome do projeto (usado como prefixo nos recursos)"
  type        = string
}

# VPC
variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
}

variable "availability_zones" {
  description = "Lista de AZs para deploy (minimo 2)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (1 por AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (1 por AZ)"
  type        = list(string)
}

# EKS
variable "eks_cluster_version" {
  description = "Versao do Kubernetes no EKS"
  type        = string
}

variable "eks_node_instance_type" {
  description = "Tipo de instancia dos nodes do EKS"
  type        = string
}

variable "eks_node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
}

variable "eks_node_min_size" {
  description = "Quantidade minima de nodes"
  type        = number
}

variable "eks_node_max_size" {
  description = "Quantidade maxima de nodes"
  type        = number
}

variable "eks_node_capacity_type" {
  description = "Tipo de capacidade dos nodes (ON_DEMAND ou SPOT)"
  type        = string
}

variable "lab_role_arn" {
  description = "ARN da IAM Role (LabRole no AWS Academy)"
  type        = string
}

# ECR
variable "service_names" {
  description = "Lista de nomes dos microsservicos para criar repositorios ECR"
  type        = list(string)
}

variable "voclabs_role_arn" {
  description = "ARN da role voclabs (AWS Academy)"
  type        = string
}
