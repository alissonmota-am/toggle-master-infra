output "queue_url" {
  description = "URL da fila SQS"
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN da fila SQS"
  value       = aws_sqs_queue.this.arn
}
