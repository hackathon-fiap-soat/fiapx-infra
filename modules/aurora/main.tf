# Aurora MySQL 8.0 (Aurora MySQL 3) com um database por serviço (ADR-005). Uma instância só: a AWS Academy
# não suporta Multi-AZ nem Enhanced Monitoring (ADR-019). Serverless v2 por padrão; se o lab recusar
# db.serverless, aurora_instance_class = "db.t4g.medium" troca para instância provisionada.
resource "aws_db_subnet_group" "this" {
  name       = var.prefix
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.prefix}-aurora"
  description = "Aurora MySQL 3306 from Lambdas and EKS only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "mysql" {
  for_each                     = var.allowed_security_group_ids
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = each.key
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "random_password" "app" {
  for_each = toset(["auth", "video"])
  length   = 32
  special  = false
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = var.prefix
  engine                  = "aurora-mysql"
  engine_version          = var.engine_version
  database_name           = null
  master_username         = "fiapx_admin"
  master_password         = random_password.master.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.this.id]
  storage_encrypted       = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = var.deletion_protection
  apply_immediately       = true

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = var.min_acu
      max_capacity = var.max_acu
    }
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier                   = "${var.prefix}-1"
  cluster_identifier           = aws_rds_cluster.this.id
  engine                       = aws_rds_cluster.this.engine
  engine_version               = aws_rds_cluster.this.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.this.name
  performance_insights_enabled = false
  monitoring_interval          = 0
  apply_immediately            = true
}

# Segredos no formato que os serviços esperam: {engine, host, port, username, password, dbname}.
resource "aws_secretsmanager_secret" "master" {
  name                    = "fiapx/${var.env}/aurora/master"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "mysql", host = aws_rds_cluster.this.endpoint, port = aws_rds_cluster.this.port,
    username = aws_rds_cluster.this.master_username, password = random_password.master.result, dbname = "mysql"
  })
}

resource "aws_secretsmanager_secret" "app" {
  for_each                = random_password.app
  name                    = "fiapx/${var.env}/db/${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each  = random_password.app
  secret_id = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode({
    engine   = "mysql", host = aws_rds_cluster.this.endpoint, port = aws_rds_cluster.this.port,
    username = "fiapx_${each.key}", password = each.value.result, dbname = "fiapx_${each.key}"
  })
}
