output "endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "master_secret_arn" {
  value = aws_secretsmanager_secret.master.arn
}

output "app_secret_arns" {
  value = { for k, s in aws_secretsmanager_secret.app : k => s.arn }
}

output "master_username" {
  value = aws_rds_cluster.this.master_username
}

output "master_password" {
  value     = random_password.master.result
  sensitive = true
}

output "app_passwords" {
  value     = { for k, p in random_password.app : k => p.result }
  sensitive = true
}

# A instância precisa existir antes de o job criar os databases.
output "writer_id" {
  value = aws_rds_cluster_instance.writer.id
}
