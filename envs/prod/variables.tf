variable "env" {
  description = "Ambiente (prefixo fiapx-<env> e /fiapx/<env>/)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "Região da AWS (o lab permite us-east-1 e us-west-2)."
  type        = string
  default     = "us-east-1"
}

variable "node_instance_type" {
  description = "Tipo dos nós do EKS (o lab permite até large, só on-demand)."
  type        = string
  default     = "t3.large"
}

variable "aurora_instance_class" {
  description = "Classe do Aurora. O lab nega db.serverless (ADR-019)."
  type        = string
  default     = "db.t3.medium"
}

variable "interface_endpoints" {
  description = "Cria VPC endpoints de interface (SQS, Secrets Manager, SSM); custam por hora."
  type        = bool
  default     = false
}

variable "protect" {
  description = "Proteção contra destroy do Aurora (deletion_protection). O destroy-all aplica com false antes."
  type        = bool
  default     = true
}

variable "alert_emails" {
  description = "E-mails do time para os alarmes das DLQs (TF_VAR_alert_emails='[\"a@b.com\"]')."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "newrelic_license_key" {
  description = "License key do New Relic (GitHub Secret); vazio = sem nri-bundle."
  type        = string
  default     = ""
  sensitive   = true
}
