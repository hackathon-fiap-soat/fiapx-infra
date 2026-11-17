variable "prefix" {
  description = "Prefixo dos nomes (fiapx-<env>)."
  type        = string
}

variable "region" {
  description = "Região da AWS."
  type        = string
}

variable "cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "interface_endpoints" {
  description = "Cria os VPC endpoints de interface (SQS, Secrets Manager, SSM). Sem eles, o tráfego sai pelo NAT."
  type        = bool
  default     = false
}
