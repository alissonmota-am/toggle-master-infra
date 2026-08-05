# VPC
output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnet_ids
}

# EKS
output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "eks_node_security_group_id" {
  description = "Security Group ID dos nodes do EKS (usar como source nos SGs de RDS e Redis)"
  value       = module.eks.node_security_group_id
}

# ECR
output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR por servico"
  value       = module.ecr.repository_urls
}
