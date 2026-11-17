# Par de chaves RSA do JWT (ADR-004). A privada vai para o Secrets Manager (só login e password leem);
# a pública é publicada no SSM para o authorizer e o video-api. A chave fica no state, que é privado.
resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "fiapx/${var.env}/auth/jwt-private-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = tls_private_key.jwt.private_key_pem
}
