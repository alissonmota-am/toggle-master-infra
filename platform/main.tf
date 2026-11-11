################################################################################
# VPC
################################################################################
module "vpc" {
  source = "../modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

################################################################################
# IAM (roles do cluster e dos nodes)
################################################################################
module "iam" {
  source = "../modules/iam"

  project_name = var.project_name
}

################################################################################
# EKS
################################################################################
module "eks" {
  source = "../modules/eks"

  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  cluster_version     = var.eks_cluster_version
  cluster_role_arn    = module.iam.cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
  node_instance_type  = var.eks_node_instance_type
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_capacity_type  = var.eks_node_capacity_type
  admin_principal_arn = var.eks_admin_principal_arn

  # Garante que as policies das roles estejam anexadas antes do cluster/node group
  depends_on = [module.iam]
}

################################################################################
# ECR
################################################################################
module "ecr" {
  source = "../modules/ecr"

  project_name  = var.project_name
  service_names = var.service_names
}
