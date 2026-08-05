aws_region   = "us-east-1"
project_name = "toggle-master-dev"

# VPC
vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.20.0/24", "10.1.30.0/24"]

# EKS
eks_cluster_version    = "1.33"
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
eks_node_min_size      = 1
eks_node_max_size      = 4
eks_node_capacity_type = "SPOT"
lab_role_arn           = "arn:aws:iam::103568492404:role/LabRole"

# ECR
service_names = ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]
