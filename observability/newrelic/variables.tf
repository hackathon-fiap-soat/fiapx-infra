variable "env" {
  description = "Ambiente observado (prefixo dos recursos na AWS e dos parâmetros SSM)."
  type        = string
  default     = "prod"
}

variable "newrelic_account_id" {
  description = "Id da conta do New Relic (GitHub Secret NEW_RELIC_ACCOUNT_ID). Não é segredo: fica legível no plan."
  type        = number
}

variable "newrelic_api_key" {
  description = "User key do New Relic (GitHub Secret NEW_RELIC_API_KEY)."
  type        = string
  sensitive   = true
}

variable "alert_emails" {
  description = "E-mails do time que recebem os alertas (GitHub Secret ALERT_EMAILS, os mesmos do SNS). Vazio = sem notificação."
  type        = list(string)
  default     = []
  sensitive   = true
}
