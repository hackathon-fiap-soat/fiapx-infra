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
  description = "db.serverless (Serverless v2) ou db.t4g.medium, se o lab recusar o Serverless v2."
  type        = string
  default     = "db.serverless"
}

variable "interface_endpoints" {
  description = "Cria VPC endpoints de interface (SQS, Secrets Manager, SSM); custam por hora."
  type        = bool
  default     = false
}

variable "protect" {
  description = "Proteções contra destroy (Aurora e bucket de vídeos). O destroy-all aplica com false antes."
  type        = bool
  default     = true
}

variable "alert_emails" {
  description = "E-mails do time para os alarmes das DLQs (TF_VAR_alert_emails='[\"a@b.com\"]')."
  type        = list(string)
  default     = []
}

variable "newrelic_license_key" {
  description = "License key do New Relic (GitHub Secret); vazio = sem nri-bundle."
  type        = string
  default     = ""
  sensitive   = true
}
