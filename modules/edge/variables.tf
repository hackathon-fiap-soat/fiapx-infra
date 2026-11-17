variable "prefix" {
  description = "Prefixo dos nomes (fiapx-<env>)."
  type        = string
}

variable "vpc_id" {
  description = "VPC do ALB e do VPC Link."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas do ALB e do VPC Link."
  type        = list(string)
}

variable "pods_security_group_id" {
  description = "Security group dos pods (o do cluster EKS)."
  type        = string
}

variable "app_port" {
  description = "Porta do nginx do video-api-web."
  type        = number
  default     = 8080
}

variable "web_origin" {
  description = "Origem do site, a única liberada no CORS."
  type        = string
}

variable "throttle_burst" {
  description = "Rate limit do stage: burst."
  type        = number
  default     = 100
}

variable "throttle_rate" {
  description = "Rate limit do stage: requisições por segundo."
  type        = number
  default     = 50
}

variable "log_retention_days" {
  description = "Retenção dos logs de acesso."
  type        = number
  default     = 7
}
