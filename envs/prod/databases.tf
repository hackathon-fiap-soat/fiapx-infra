# Cria os databases e os usuários de aplicação rodando o entregável sql/create-databases.sql dentro do
# cluster (o Aurora fica em subnet privada; o runner do GitHub não o alcança). Idempotente: o job roda de
# novo quando o SQL ou as senhas mudam.
resource "kubernetes_namespace_v1" "infra" {
  metadata {
    name = "fiapx-infra"
  }
  depends_on = [module.eks]
}

resource "kubernetes_secret_v1" "databases" {
  metadata {
    name      = "create-databases"
    namespace = kubernetes_namespace_v1.infra.metadata[0].name
  }
  data = {
    "MYSQL_HOST"           = module.aurora.endpoint
    "MYSQL_USER"           = module.aurora.master_username
    "MYSQL_PWD"            = module.aurora.master_password
    "FIAPX_AUTH_PASSWORD"  = module.aurora.app_passwords["auth"]
    "FIAPX_VIDEO_PASSWORD" = module.aurora.app_passwords["video"]
    "create-databases.sql" = file("${path.module}/../../sql/create-databases.sql")
  }
}

resource "kubernetes_job_v1" "databases" {
  metadata {
    name      = "create-databases-${substr(sha1(join("", [kubernetes_secret_v1.databases.data["create-databases.sql"], module.aurora.app_passwords["auth"], module.aurora.app_passwords["video"]])), 0, 8)}"
    namespace = kubernetes_namespace_v1.infra.metadata[0].name
  }

  spec {
    backoff_limit              = 6
    ttl_seconds_after_finished = 3600
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name    = "mysql"
          image   = "mysql:8.0"
          command = ["sh", "-c"]
          args = [<<-SH
            set -e
            {
              printf "SET @fiapx_auth_password = '%s';\n" "$FIAPX_AUTH_PASSWORD"
              printf "SET @fiapx_video_password = '%s';\n" "$FIAPX_VIDEO_PASSWORD"
              cat /sql/create-databases.sql
            } | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER"
            echo "databases e usuários criados"
          SH
          ]
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.databases.metadata[0].name
            }
          }
          volume_mount {
            name       = "sql"
            mount_path = "/sql"
          }
        }
        volume {
          name = "sql"
          secret {
            secret_name = kubernetes_secret_v1.databases.metadata[0].name
            items {
              key  = "create-databases.sql"
              path = "create-databases.sql"
            }
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "10m"
  }

  depends_on = [module.aurora]
}
