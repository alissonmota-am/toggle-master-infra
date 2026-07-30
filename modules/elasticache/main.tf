################################################################################
# Subnet Group
################################################################################
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

################################################################################
# Security Group — acesso somente pelos nodes do EKS
################################################################################
resource "aws_security_group" "this" {
  name_prefix = "${var.project_name}-redis-"
  description = "Acesso ao Redis somente pelo EKS"
  vpc_id      = var.vpc_id

  ingress {
    from_port                = 6379
    to_port                  = 6379
    protocol                 = "tcp"
    security_groups          = [var.eks_node_security_group_id]
    description              = "Acesso dos nodes EKS ao Redis"
  }

  tags = {
    Name = "${var.project_name}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# ElastiCache Redis
################################################################################
resource "aws_elasticache_cluster" "this" {
  cluster_id      = "${var.project_name}-redis"
  engine          = "redis"
  engine_version  = "7.0"
  node_type       = var.node_type
  num_cache_nodes = 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  tags = {
    Name = "${var.project_name}-redis"
  }
}
