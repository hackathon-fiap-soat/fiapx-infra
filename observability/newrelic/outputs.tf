output "dashboards" {
  description = "Links dos dashboards criados."
  value       = { for k, d in newrelic_one_dashboard_json.this : k => d.permalink }
}

output "alert_policy_id" {
  description = "Id da política de alertas."
  value       = newrelic_alert_policy.this.id
}

output "synthetics_monitor" {
  description = "URL verificada pelo monitor Synthetics (vazio sem ambiente)."
  value       = local.synthetics ? newrelic_synthetics_monitor.health[0].uri : ""
}
