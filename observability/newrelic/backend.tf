# State próprio no mesmo bucket do envs/prod (ADR-021): um erro de painel ou alerta não trava o apply da AWS.
# O bucket fiapx-tfstate-<account_id> é passado por -backend-config=bucket=... pelo workflow newrelic.yml.
terraform {
  backend "s3" {
    key          = "fiapx-infra/newrelic.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
