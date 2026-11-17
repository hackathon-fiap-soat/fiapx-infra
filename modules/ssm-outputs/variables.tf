variable "env" {
  description = "Ambiente (prefixo /fiapx/<env>/)."
  type        = string
}

variable "parameters" {
  description = "Chave relativa => valor."
  type        = map(string)
}
