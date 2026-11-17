variable "repositories" {
  description = "Nomes dos repositórios de imagem."
  type        = list(string)
  default     = ["fiapx-video-api", "fiapx-video-processor"]
}
