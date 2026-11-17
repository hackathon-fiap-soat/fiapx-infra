# Dashboards no formato de export do New Relic; o id da conta entra pelo template (ADR-021).
# Para mudar um widget: edite o JSON, abra PR e confira o plan.
locals {
  dashboards = {
    processamento = "dashboards/processamento.json.tftpl"
    kubernetes    = "dashboards/kubernetes.json.tftpl"
  }
}

resource "newrelic_one_dashboard_json" "this" {
  for_each = local.dashboards

  json = templatefile("${path.module}/${each.value}", { account_id = var.newrelic_account_id })
}
