# Política e condições NRQL da doc fiapx-docs/07-observabilidade/observabilidade.md#alertas (ADR-021).
resource "newrelic_alert_policy" "this" {
  name                = "FIAP X — ${var.env}"
  incident_preference = "PER_CONDITION"
}

locals {
  cluster = "fiapx-${var.env}"

  # janela, duração e ocorrências seguem a tabela da documentação.
  conditions = {
    taxa_de_falha = {
      name        = "Taxa de falha de processamento > 10%"
      description = "Ver o widget \"Motivos de falha\" e os logs do fiapx-video-processor."
      query       = "SELECT percentage(count(*), WHERE to_state = 'COMPENSATED') FROM VideoSagaTransition WHERE to_state IN ('COMPLETED', 'COMPENSATED')"
      threshold   = 10
      window      = 900
      duration    = 900
      occurrences = "all"
      method      = "event_flow"
    }
    erros_5xx = {
      name        = "Erros 5xx no video-api > 2%"
      description = "Ver TransactionError e os logs do video-api."
      query       = "SELECT percentage(count(*), WHERE http.statusCode >= 500) FROM Transaction WHERE appName = 'fiapx-video-api' AND transactionType = 'Web'"
      threshold   = 2
      window      = 300
      duration    = 300
      occurrences = "all"
      method      = "event_flow"
    }
    sagas_vencidas = {
      name        = "Sagas vencidas"
      description = "Conferir outbox-relay, saga-consumer e o CronJob. Sem sinal: o CronJob parou ou o daemon compartilhado caiu."
      query       = "SELECT max(overdue_count) FROM SagaTimeoutCheck"
      threshold   = 0
      window      = 60
      duration    = 300
      occurrences = "all"
      method      = "event_flow"
    }
    pod_pendente = {
      name        = "Pod pendente por 10 minutos"
      description = "Falta de CPU ou memória nos nós: ver \"Eventos do Kubernetes\" no dashboard do EKS."
      query       = "SELECT uniqueCount(podName) FROM K8sPodSample WHERE clusterName = '${local.cluster}' AND status = 'Pending' AND createdKind != 'Job'"
      threshold   = 0
      window      = 300
      duration    = 600
      occurrences = "all"
      method      = "event_flow"
    }
    falha_email = {
      name        = "Falha no envio de e-mail"
      description = "Logs da Lambda fiapx-${var.env}-notification, credenciais SMTP e itens FAILED no DynamoDB."
      query       = "SELECT count(*) FROM AwsLambdaInvocationError WHERE aws.lambda.arn LIKE '%:function:fiapx-${var.env}-notification'"
      threshold   = 0
      window      = 300
      duration    = 300
      occurrences = "at_least_once"
      method      = "event_timer"
    }
    synthetics = {
      name        = "API fora do ar (Synthetics)"
      description = "Conferir o API Gateway, o ALB e os pods do video-api."
      query       = "SELECT count(*) FROM SyntheticCheck WHERE monitorName = '${local.monitor_name}' AND result = 'FAILED'"
      threshold   = 0
      window      = 300
      duration    = 600
      occurrences = "at_least_once"
      method      = "event_timer"
    }
  }
}

resource "newrelic_nrql_alert_condition" "this" {
  for_each = local.conditions

  policy_id                    = newrelic_alert_policy.this.id
  type                         = "static"
  name                         = each.value.name
  description                  = each.value.description
  enabled                      = true
  violation_time_limit_seconds = 86400

  aggregation_window = each.value.window
  aggregation_method = each.value.method
  aggregation_delay  = each.value.method == "event_flow" ? 120 : null
  aggregation_timer  = each.value.method == "event_timer" ? 60 : null

  # Só as sagas vencidas avisam quando o sinal some (o CronJob roda a cada minuto).
  expiration_duration            = each.key == "sagas_vencidas" ? 600 : null
  open_violation_on_expiration   = each.key == "sagas_vencidas"
  close_violations_on_expiration = false

  nrql {
    query = each.value.query
  }

  critical {
    operator              = "above"
    threshold             = each.value.threshold
    threshold_duration    = each.value.duration
    threshold_occurrences = each.value.occurrences
  }
}
