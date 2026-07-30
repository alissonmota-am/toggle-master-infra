variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
  type        = string
}

variable "queue_name" {
  description = "Nome da fila SQS"
  type        = string
}

variable "table_name" {
  description = "Nome da tabela DynamoDB"
  type        = string
}
