output "repository_urls" {
  description = "Map de nome do servico para URL do repositorio ECR"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "registry_id" {
  description = "ID do registry ECR"
  value       = values(aws_ecr_repository.this)[0].registry_id
}
