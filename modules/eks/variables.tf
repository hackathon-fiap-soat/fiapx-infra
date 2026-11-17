variable "prefix" {
  description = "Prefixo dos nomes (fiapx-<env>); também é o nome do cluster."
  type        = string
}

variable "lab_role_name" {
  description = "Role pré-criada da AWS Academy usada pelo cluster e pelos nós."
  type        = string
  default     = "LabRole"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes."
  type        = string
  default     = "1.35" # 1.33 já está em suporte estendido (6x mais caro)
}

variable "private_subnet_ids" {
  description = "Subnets privadas do cluster e dos nós."
  type        = list(string)
}

variable "node_instance_type" {
  description = "Tipo dos nós (o lab permite até large)."
  type        = string
  default     = "t3.large"
}

variable "node_min" {
  description = "Mínimo de nós."
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Máximo de nós (teto do lab: 32 vCPUs e 9 instâncias)."
  type        = number
  default     = 4
}

variable "node_disk_gb" {
  description = "Disco de cada nó (o lab permite até 100 GB)."
  type        = number
  default     = 30
}
