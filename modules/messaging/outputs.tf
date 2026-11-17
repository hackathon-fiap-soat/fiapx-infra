output "queues" {
  description = "Filas por chave: { url, arn }."
  value       = { for k, q in aws_sqs_queue.this : k => { url = q.url, arn = q.arn } }
}

output "dlq_urls" {
  value = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "video_uploaded_arn" {
  value = aws_sqs_queue.this["video-uploaded"].arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alertas.arn
}
