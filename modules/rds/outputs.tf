output "endpoint" {
  description = "Endpoint do RDS (host para DATABASE_URL)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta do RDS"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco de dados"
  value       = aws_db_instance.this.db_name
}
