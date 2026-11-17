# Ambiente prod na AWS Academy Learner Lab (ADR-019). Ordem: rede → EKS → add-ons; Aurora, filas, bucket,
# ECR, borda (API Gateway + ALB), site e JWT; no fim, os databases e os parâmetros SSM.
data "aws_caller_identity" "this" {}

locals {
  prefix     = "fiapx-${var.env}"
  account_id = data.aws_caller_identity.this.account_id
  # Nomes de bucket são globais na AWS: o id da conta evita colisão.
  videos_bucket = "${local.prefix}-videos-${local.account_id}"
  web_bucket    = "${local.prefix}-web-${local.account_id}"
}

module "network" {
  source              = "../../modules/network"
  prefix              = local.prefix
  region              = var.region
  interface_endpoints = var.interface_endpoints
}

module "eks" {
  source             = "../../modules/eks"
  prefix             = local.prefix
  private_subnet_ids = module.network.private_subnet_ids
  node_instance_type = var.node_instance_type
}

module "eks_addons" {
  source               = "../../modules/eks-addons"
  cluster_name         = module.eks.cluster_name
  region               = var.region
  vpc_id               = module.network.vpc_id
  newrelic_license_key = var.newrelic_license_key
  depends_on           = [module.eks]
}

module "aurora" {
  source              = "../../modules/aurora"
  prefix              = local.prefix
  env                 = var.env
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  instance_class      = var.aurora_instance_class
  deletion_protection = var.protect
  allowed_security_group_ids = {
    "Lambdas auth and notification" = module.network.lambda_security_group_id
    "EKS nodes and pods"            = module.eks.cluster_security_group_id
  }
}

module "web_hosting" {
  source      = "../../modules/web-hosting"
  bucket_name = local.web_bucket
}

module "messaging" {
  source            = "../../modules/messaging"
  prefix            = local.prefix
  videos_bucket_arn = "arn:aws:s3:::${local.videos_bucket}"
  alert_emails      = var.alert_emails
}

module "storage" {
  source                   = "../../modules/storage"
  bucket_name              = local.videos_bucket
  web_origin               = module.web_hosting.url
  video_uploaded_queue_arn = module.messaging.video_uploaded_arn
  protect                  = var.protect
  depends_on               = [module.messaging] # a política da fila precisa existir antes da notificação
}

module "ecr" {
  source = "../../modules/ecr"
}

module "edge" {
  source                 = "../../modules/edge"
  prefix                 = local.prefix
  vpc_id                 = module.network.vpc_id
  vpc_cidr               = module.network.vpc_cidr
  private_subnet_ids     = module.network.private_subnet_ids
  pods_security_group_id = module.eks.cluster_security_group_id
  web_origin             = module.web_hosting.url
}

module "jwt" {
  source = "../../modules/jwt"
  env    = var.env
}

module "ssm" {
  source = "../../modules/ssm-outputs"
  env    = var.env
  parameters = merge(
    {
      "region"                          = var.region
      "vpc/private_subnet_ids"          = join(",", module.network.private_subnet_ids)
      "vpc/lambda_security_group_id"    = module.network.lambda_security_group_id
      "eks/cluster_name"                = module.eks.cluster_name
      "aurora/endpoint"                 = module.aurora.endpoint
      "aurora/port"                     = tostring(module.aurora.port)
      "aurora/secret_arn"               = module.aurora.master_secret_arn
      "db/auth/secret_arn"              = module.aurora.app_secret_arns["auth"]
      "db/video/secret_arn"             = module.aurora.app_secret_arns["video"]
      "auth/jwt_private_key_secret_arn" = module.jwt.private_key_secret_arn
      "auth/jwt_public_key"             = module.jwt.public_key_pem
      "s3/videos_bucket"                = module.storage.bucket
      "apigw/api_id"                    = module.edge.api_id
      "apigw/url"                       = module.edge.api_url
      "apigw/vpc_link_id"               = module.edge.vpc_link_id
      "alb/target_group_arn"            = module.edge.target_group_arn
      "alb/listener_arn"                = module.edge.listener_arn
      "web/bucket"                      = module.web_hosting.bucket
      "web/url"                         = module.web_hosting.url
      "sns/alerts_topic_arn"            = module.messaging.alerts_topic_arn
    },
    { for k, q in module.messaging.queues : "sqs/${k}/url" => q.url },
    { for k, q in module.messaging.queues : "sqs/${k}/arn" => q.arn },
    { for k, u in module.messaging.dlq_urls : "sqs/${k}-dlq/url" => u },
    { for k, u in module.ecr.urls : "ecr/${k}/url" => u },
  )
}
