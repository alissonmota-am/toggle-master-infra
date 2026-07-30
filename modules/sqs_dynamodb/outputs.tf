output "queue_url" {
  description = "URL da fila SQS (usar em AWS_SQS_URL)"
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN da fila SQS"
  value       = aws_sqs_queue.this.arn
}

output "table_name" {
  description = "Nome da tabela DynamoDB"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.this.arn
}
