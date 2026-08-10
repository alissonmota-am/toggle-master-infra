variable "table_name" {
  description = "Nome da tabela DynamoDB"
  type        = string
}

variable "hash_key" {
  description = "Nome da partition key"
  type        = string
}

variable "hash_key_type" {
  description = "Tipo da partition key (S, N, B)"
  type        = string
}
