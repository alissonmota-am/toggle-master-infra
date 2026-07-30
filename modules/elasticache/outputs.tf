output "endpoint" {
  description = "Endpoint do Redis (host para REDIS_URL)"
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "port" {
  description = "Porta do Redis"
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}
