# State remoto no S3 com lock nativo (ADR-002). O bucket fiapx-tfstate-<account_id> é criado pelo próprio
# workflow antes do init e passado por -backend-config=bucket=... (ADR-019: não há bootstrap manual).
terraform {
  backend "s3" {
    key          = "fiapx-infra/prod.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
