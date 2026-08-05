variable "project_name" {
  description = "Nome do projeto (prefixo dos repositorios)"
  type        = string
}

variable "service_names" {
  description = "Lista de nomes dos microsservicos"
  type        = list(string)
}
