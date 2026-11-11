variable "function_name" {
  description = "Nome da funcao Lambda"
  type        = string
  default     = "toggle-master-self-healing"
}

variable "github_token" {
  description = "GitHub PAT (fine-grained, Actions: Read and write no repositorio alvo) usado para disparar o workflow"
  type        = string
  sensitive   = true
}

variable "webhook_token" {
  description = "Token compartilhado com o Alertmanager; a Function URL e publica e rejeita quem nao o enviar"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "Repositorio que contem o workflow de self-healing (owner/nome)"
  type        = string
  default     = "alissonmota-am/toggle-master-infra"
}

variable "github_workflow" {
  description = "Arquivo do workflow a ser disparado"
  type        = string
  default     = "self-healing.yml"
}

variable "github_ref" {
  description = "Branch onde o workflow existe (workflow_dispatch aceita branches que nao sao a padrao)"
  type        = string
  default     = "develop"
}

variable "allowed_services" {
  description = "Servicos que a Lambda pode reiniciar; qualquer outro nome recebido num alerta e ignorado"
  type        = list(string)
  default     = ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]
}

variable "log_retention_days" {
  description = "Retencao dos logs da Lambda no CloudWatch"
  type        = number
  default     = 7
}
