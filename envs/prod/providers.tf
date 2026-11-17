provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "fiapx", Environment = var.env, Repository = "fiapx-infra", ManagedBy = "terraform" }
  }
}

# Helm e Kubernetes falam com o cluster criado aqui, com o token das credenciais do lab (criador do cluster).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  token                  = data.aws_eks_cluster_auth.this.token
}
