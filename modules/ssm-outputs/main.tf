# Publica em /fiapx/<env>/... tudo o que os outros repositórios leem (ADR-001,
# fiapx-docs/06-deploy/parametros-ssm.md).
resource "aws_ssm_parameter" "this" {
  for_each = var.parameters
  name     = "/fiapx/${var.env}/${each.key}"
  type     = "String"
  tier     = length(each.value) > 4096 ? "Advanced" : "Standard"
  value    = each.value
}
