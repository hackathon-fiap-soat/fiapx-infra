variable "prefix" {
  description = "Prefixo dos nomes (fiapx-<env>)."
  type        = string
}

variable "env" {
  description = "Ambiente (nome dos segredos fiapx/<env>/...)."
  type        = string
}

variable "vpc_id" {
  description = "VPC do banco."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas do banco."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups que podem conectar na 3306 (descrição => id)."
  type        = map(string)
}

variable "engine_version" {
  description = "Versão do Aurora MySQL 3 (compatível com MySQL 8.0)."
  type        = string
  default     = "8.0.mysql_aurora.3.08.2"
}

variable "instance_class" {
  description = "Classe da instância. O lab nega db.serverless (ADR-019); em conta própria, db.serverless volta a valer."
  type        = string
  default     = "db.t3.medium"
}

variable "min_acu" {
  description = "Capacidade mínima do Serverless v2."
  type        = number
  default     = 0.5
}

variable "max_acu" {
  description = "Capacidade máxima do Serverless v2."
  type        = number
  default     = 2
}

variable "deletion_protection" {
  description = "Proteção contra exclusão; o destroy-all desliga antes de destruir."
  type        = bool
  default     = true
}
