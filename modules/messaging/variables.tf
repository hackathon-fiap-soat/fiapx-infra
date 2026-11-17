variable "prefix" {
  description = "Prefixo dos nomes (fiapx-<env>)."
  type        = string
}

variable "videos_bucket_arn" {
  description = "Bucket de vídeos que publica ObjectCreated na video-uploaded."
  type        = string
}

variable "alert_emails" {
  description = "E-mails do time que recebem os alarmes (cada um confirma a assinatura do SNS)."
  type        = list(string)
  default     = []
  sensitive   = true
}
