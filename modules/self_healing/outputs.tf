output "function_url" {
  description = "URL HTTPS da Function URL (destino do webhook do Alertmanager)"
  value       = aws_lambda_function_url.this.function_url
}

output "function_name" {
  description = "Nome da funcao Lambda"
  value       = aws_lambda_function.this.function_name
}
