# Monitor de disponibilidade da API. O endereço do API Gateway muda a cada sessão da AWS Academy, por isso
# ele é lido do SSM e o monitor só existe enquanto o ambiente existe (deploy-all cria, destroy-all remove).
# by_path não falha se o parâmetro não existir: sem ambiente, nenhum monitor.
data "aws_ssm_parameters_by_path" "apigw" {
  path = "/fiapx/${var.env}/apigw"
}

locals {
  apigw_params = zipmap(data.aws_ssm_parameters_by_path.apigw.names, nonsensitive(data.aws_ssm_parameters_by_path.apigw.values))
  api_url      = lookup(local.apigw_params, "/fiapx/${var.env}/apigw/url", "")
  synthetics   = local.api_url != ""
  monitor_name = "FIAP X — health (${var.env})"
}

resource "newrelic_synthetics_monitor" "health" {
  count = local.synthetics ? 1 : 0

  name             = local.monitor_name
  type             = "SIMPLE"
  status           = "ENABLED"
  period           = "EVERY_5_MINUTES"
  uri              = "${local.api_url}/api/health/ready"
  locations_public = ["US_EAST_1"]
  verify_ssl       = true
}
