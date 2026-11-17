output "api_url" {
  description = "URL do API Gateway (as rotas são criadas pelos serviços)."
  value       = module.edge.api_url
}

output "web_url" {
  description = "URL do site (S3 website)."
  value       = module.web_hosting.url
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ssm_parameters" {
  description = "Parâmetros publicados em /fiapx/<env>/."
  value       = module.ssm.names
}
