#!/bin/bash
# Executado pela imagem mysql:8.0 na primeira inicialização do volume (/docker-entrypoint-initdb.d).
# Roda o mesmo sql/create-databases.sql usado na AWS, passando as senhas locais por variável de sessão.
set -euo pipefail

: "${FIAPX_AUTH_DB_PASSWORD:?defina FIAPX_AUTH_DB_PASSWORD}"
: "${FIAPX_VIDEO_DB_PASSWORD:?defina FIAPX_VIDEO_DB_PASSWORD}"

sql_quote() { printf "'%s'" "${1//\'/\'\'}"; }

{
  echo "SET @fiapx_auth_password  = $(sql_quote "$FIAPX_AUTH_DB_PASSWORD");"
  echo "SET @fiapx_video_password = $(sql_quote "$FIAPX_VIDEO_DB_PASSWORD");"
  cat /fiapx-sql/create-databases.sql
} | mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD"

echo "fiapx: databases fiapx_auth e fiapx_video criados"
