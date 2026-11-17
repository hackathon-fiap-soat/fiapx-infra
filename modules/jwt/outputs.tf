output "private_key_secret_arn" {
  value = aws_secretsmanager_secret.jwt.arn
}

output "public_key_pem" {
  value = tls_private_key.jwt.public_key_pem
}
