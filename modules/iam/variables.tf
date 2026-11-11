variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "sqs_queue_prefix" {
  description = "Prefixo do nome das filas SQS que os pods podem acessar"
  type        = string
  default     = "analytics-service-"
}

variable "dynamodb_table_prefix" {
  description = "Prefixo do nome das tabelas DynamoDB que os pods podem acessar"
  type        = string
  default     = "AnalyticsServiceEvents"
}
