variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
}

variable "availability_zones" {
  description = "Lista de AZs"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
}
