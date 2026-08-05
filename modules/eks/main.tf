################################################################################
# Security Group adicional do Cluster (referenciado por RDS e ElastiCache)
################################################################################
resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-eks-"
  description = "Security group adicional para o cluster EKS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-eks-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Permite kubelet (logs/exec) do control plane para os nodes
resource "aws_security_group_rule" "kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description              = "Permite kubelet (logs/exec) do control plane para os nodes"
}

################################################################################
# EKS Cluster
################################################################################
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-cluster"
  version  = var.cluster_version
  role_arn = var.role_arn

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.cluster.id]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

################################################################################
# EKS Access Entry — permite LabRole acessar o cluster como admin
################################################################################
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

################################################################################
# EKS Access Entry — permite voclabs (AWS Academy) acessar o cluster
################################################################################
resource "aws_eks_access_entry" "voclabs" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.voclabs_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "voclabs" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.voclabs_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.voclabs]
}

################################################################################
# EKS Node Group
################################################################################
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = var.role_arn
  subnet_ids      = var.subnet_ids
  capacity_type   = var.node_capacity_type
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  tags = {
    Name = "${var.project_name}-nodes"
  }

  depends_on = [aws_eks_cluster.this]
}
