terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "toggle-master-terraform-state-103568492404"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}
