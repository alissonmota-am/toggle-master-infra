################################################################################
# Role do Cluster EKS (control plane)
################################################################################
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

################################################################################
# Role dos Nodes (EC2)
#
# Os pods alcancam o IMDS do node (hop limit 2, ver modulo eks) e usam esta role
# para acessar SQS e DynamoDB (evaluation-service e analytics-service).
################################################################################
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Acesso minimo dos pods aos recursos do analytics (fila e tabela)
data "aws_iam_policy_document" "node_workloads" {
  statement {
    sid = "SqsAnalytics"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = ["arn:aws:sqs:*:${data.aws_caller_identity.current.account_id}:${var.sqs_queue_prefix}*"]
  }

  statement {
    sid = "DynamoDbAnalytics"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = ["arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_prefix}*"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "node_workloads" {
  name   = "${var.project_name}-node-workloads"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node_workloads.json
}
