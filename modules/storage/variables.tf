variable "bucket_name" {
  description = "Nome do bucket de vídeos (global na AWS: inclui o id da conta)."
  type        = string
}

variable "web_origin" {
  description = "Origem do site (CORS do POST de upload), sem barra no fim."
  type        = string
}

variable "video_uploaded_queue_arn" {
  description = "Fila que recebe os eventos ObjectCreated de uploads/."
  type        = string
}
