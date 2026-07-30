################################################################################
# Subnet Group
################################################################################
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

################################################################################
# Security Group — acesso somente pelos nodes do EKS
################################################################################
resource "aws_security_group" "this" {
  name_prefix = "${var.project_name}-rds-"
  description = "Acesso ao RDS somente pelo EKS"
  vpc_id      = var.vpc_id

  ingress {
    from_port                = 5432
    to_port                  = 5432
    protocol                 = "tcp"
    security_groups          = [var.eks_node_security_group_id]
    description              = "Acesso dos nodes EKS ao RDS"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# RDS PostgreSQL
################################################################################
resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16.9"

  instance_class    = var.instance_class
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.username
  password = var.password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  publicly_accessible = false
  multi_az            = false
  deletion_protection = false

  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-db"
  }
}
