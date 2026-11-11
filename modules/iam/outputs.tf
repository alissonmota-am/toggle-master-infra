output "cluster_role_arn" {
  description = "ARN da role do control plane do EKS"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN da role dos nodes do EKS"
  value       = aws_iam_role.node.arn
}
