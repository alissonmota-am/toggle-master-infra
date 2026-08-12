terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket       = "toggle-master-terraform-state-103568492404"
    region       = "us-east-1"
    key          = "placeholder"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.platform_state_bucket
    key    = var.platform_state_key
    region = var.aws_region
  }
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.platform.outputs.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.platform.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.eks_cluster_certificate_authority)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.platform.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.eks_cluster_certificate_authority)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
