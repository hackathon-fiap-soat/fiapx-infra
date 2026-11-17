variable "name" {
  description = "Nome do bucket (global na AWS)."
  type        = string
}

variable "region" {
  description = "Região do bucket."
  type        = string
  default     = "us-east-1"
}

variable "force_destroy" {
  description = "Apaga os objetos antes de apagar o bucket no destroy."
  type        = bool
  default     = false
}
