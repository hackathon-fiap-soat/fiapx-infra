# Filas compartilhadas (spec §7.1) com DLQ própria, iguais às do ambiente local (local/init/localstack).
# A notification-commands é criada pelo fiapx-notification. Alarme em toda DLQ com mensagem visível,
# publicado num tópico SNS (e-mail do time); as métricas ficam no CloudWatch (ADR-019).
locals {
  filas = {
    video-uploaded      = { visibility = 60, max_receive = 5, fifo = false }
    processing-commands = { visibility = 300, max_receive = 3, fifo = false }
    saga-replies        = { visibility = 60, max_receive = 3, fifo = true }
  }
}

resource "aws_sqs_queue" "dlq" {
  for_each                  = local.filas
  name                      = "${var.prefix}-${each.key}-dlq${each.value.fifo ? ".fifo" : ""}"
  fifo_queue                = each.value.fifo ? true : null
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "this" {
  for_each                    = local.filas
  name                        = "${var.prefix}-${each.key}${each.value.fifo ? ".fifo" : ""}"
  fifo_queue                  = each.value.fifo ? true : null
  content_based_deduplication = each.value.fifo ? false : null
  visibility_timeout_seconds  = each.value.visibility
  receive_wait_time_seconds   = 20
  message_retention_seconds   = 345600
  sqs_managed_sse_enabled     = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive
  })
}

# O S3 publica os eventos ObjectCreated de uploads/ na video-uploaded.
resource "aws_sqs_queue_policy" "video_uploaded" {
  queue_url = aws_sqs_queue.this["video-uploaded"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.this["video-uploaded"].arn
      Condition = { ArnEquals = { "aws:SourceArn" = var.videos_bucket_arn } }
    }]
  })
}

resource "aws_sns_topic" "alertas" {
  name = "${var.prefix}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each            = aws_sqs_queue.dlq
  alarm_name          = "${each.value.name}-com-mensagens"
  alarm_description   = "Mensagem na DLQ ${each.value.name}: investigar e reprocessar."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alertas.arn]
}
