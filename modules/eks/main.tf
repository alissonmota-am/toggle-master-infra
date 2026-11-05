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
# LabRole: SEM access entry STANDARD (de proposito)
#
# No AWS Academy a LabRole e a role do cluster E dos nodes. Um principal so pode
# ter UMA access entry; uma entry STANDARD (admin) faz o EKS tratar o kubelet como
# usuario comum, em vez de system:node:*. Consequencia: o signer do EKS nao emite
# o certificado kubelet-serving, e kubectl logs/exec/port-forward e o scrape do
# kubelet pelo Prometheus falham com "tls: internal error".
#
# Sem a entry STANDARD, o node group gerenciado registra a LabRole como node
# (EC2_LINUX / aws-auth: system:node:{{EC2PrivateDNSName}}, grupo system:nodes) e
# os certificados sao emitidos automaticamente. O acesso administrativo ao
# cluster vem da voclabs (entry abaixo), que e quem roda kubectl e os workflows.
################################################################################

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
# Launch Template dos nodes — so metadata (IMDSv2 com hop limit 2)
#
# Com hop limit 1 (padrao), pods nao alcancam o IMDS do node e ficam sem
# credenciais AWS (o evaluation/analytics falham no SQS/DynamoDB com
# "NoCredentialProviders"/"Unable to locate credentials"). Hop limit 2 permite
# que os pods usem a role do node (LabRole). No AWS Academy nao e possivel criar
# roles por servico (IRSA/Pod Identity), entao esta e a alternativa viavel.
#
# Nao define AMI, tipo de instancia nem security groups: o EKS continua usando a
# AMI otimizada e anexando o SG do cluster.
################################################################################
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.project_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-nodes"
    }
  }
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

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

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
