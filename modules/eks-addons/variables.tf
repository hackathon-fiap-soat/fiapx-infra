variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "region" {
  description = "Região da AWS."
  type        = string
}

variable "vpc_id" {
  description = "VPC do cluster (o controller não descobre sozinho sem IMDS do pod em alguns casos)."
  type        = string
}

variable "newrelic_license_key" {
  description = "License key do New Relic; vazio = nri-bundle não é instalado."
  type        = string
  default     = ""
  sensitive   = true
}

variable "chart_versions" {
  description = "Versões fixas dos charts."
  type = object({
    aws_load_balancer_controller = string
    metrics_server               = string
    keda                         = string
    nri_bundle                   = string
  })
  default = {
    aws_load_balancer_controller = "3.6.1"
    metrics_server               = "3.13.1"
    keda                         = "2.20.2"
    nri_bundle                   = "8.0.38"
  }
}
