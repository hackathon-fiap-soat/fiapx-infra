# E-mail do time: todo issue da política vai para os endereços de ALERT_EMAILS (os mesmos do SNS).
locals {
  notify = nonsensitive(length(var.alert_emails)) > 0
}

resource "newrelic_notification_destination" "email" {
  count = local.notify ? 1 : 0

  name = "FIAP X — e-mail do time (${var.env})"
  type = "EMAIL"

  property {
    key   = "email"
    value = join(",", var.alert_emails)
  }
}

resource "newrelic_notification_channel" "email" {
  count = local.notify ? 1 : 0

  name           = "FIAP X — e-mail do time (${var.env})"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.email[0].id

  property {
    key   = "subject"
    value = "[FIAP X ${var.env}] {{issueTitle}}"
  }
}

resource "newrelic_workflow" "email" {
  count = local.notify ? 1 : 0

  name                  = "FIAP X — e-mail do time (${var.env})"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "Política FIAP X — ${var.env}"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.this.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email[0].id
  }
}
