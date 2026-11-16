#!/bin/bash
# Lista e confere os recursos do ambiente local. Sai com código 1 se algo estiver faltando.
# Uso (dentro de fiapx-infra/local):  ./scripts/verificar.sh
# Só precisa do Docker: os comandos da AWS rodam dentro do container do LocalStack (awslocal).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FALHAS=0
ok()    { printf '  \033[32m✔\033[0m %s\n' "$*"; }
falha() { printf '  \033[31m✘\033[0m %s\n' "$*"; FALHAS=$((FALHAS + 1)); }
lista() { sed 's/^/    /'; }
secao() { printf '\n\033[1m%s\033[0m\n' "$*"; }
aws_()  { docker compose exec -T localstack awslocal "$@"; }
sql()   { docker compose exec -T mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "$1" 2>/dev/null' _ "$1"; }
confere() { # confere <descrição> <saída esperada contida> <saída obtida>
  if grep -qF -- "$2" <<<"$3"; then ok "$1"; else falha "$1 (esperado: $2)"; fi
}

secao "Containers"
for s in mysql localstack mailpit; do
  estado=$(docker compose ps --format '{{.Health}}' "$s" 2>/dev/null)
  if [ "$estado" = "healthy" ]; then ok "$s saudável"
  else falha "$s não está saudável (${estado:-parado}). Rode: docker compose up -d --wait"; fi
done
[ "$FALHAS" -gt 0 ] && { echo; echo "Ambiente fora do ar."; exit 1; }

secao "MySQL (Aurora local)"
dbs=$(sql "SHOW DATABASES")
confere "database fiapx_auth" fiapx_auth "$dbs"
confere "database fiapx_video" fiapx_video "$dbs"
for u in auth video; do
  grants=$(sql "SHOW GRANTS FOR 'fiapx_${u}'@'%'")
  confere "usuário fiapx_${u} com acesso só a fiapx_${u}.*" "ON \`fiapx_${u}\`.*" "$grants"
  if grep -q "ON \*\.\*.*\(SELECT\|ALL\)" <<<"$grants"; then falha "fiapx_${u} tem privilégio global"; fi
done
outro=$(docker compose exec -T mysql sh -c 'mysql -ufiapx_auth -p"$FIAPX_AUTH_DB_PASSWORD" -e "USE fiapx_video" 2>&1')
confere "fiapx_auth não acessa fiapx_video" "Access denied" "$outro"

secao "S3"
aws_ s3 ls | lista
confere "bucket fiapx-local-videos" fiapx-local-videos "$(aws_ s3 ls)"
confere "CORS só com POST" '"POST"' "$(aws_ s3api get-bucket-cors --bucket fiapx-local-videos)"
confere "lifecycle uploads/ e results/" "expira-results" "$(aws_ s3api get-bucket-lifecycle-configuration --bucket fiapx-local-videos)"
confere "notificação ObjectCreated em uploads/" "uploads/" "$(aws_ s3api get-bucket-notification-configuration --bucket fiapx-local-videos)"

secao "SQS"
filas=$(aws_ sqs list-queues --query 'QueueUrls[]' --output text | tr '\t' '\n')
lista <<<"$filas"
for f in video-uploaded processing-commands saga-replies notification-commands; do
  sufixo=""; [ "$f" = saga-replies ] && sufixo=".fifo"
  confere "fila fiapx-local-${f}${sufixo}" "/fiapx-local-${f}${sufixo}" "$filas"
  confere "DLQ fiapx-local-${f}-dlq${sufixo}" "/fiapx-local-${f}-dlq${sufixo}" "$filas"
done
confere "video-uploaded com DLQ após 5 recebimentos" 'maxReceiveCount\": 5' \
  "$(aws_ sqs get-queue-attributes --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/fiapx-local-video-uploaded --attribute-names RedrivePolicy)"

secao "DynamoDB"
tabela=$(aws_ dynamodb describe-table --table-name fiapx-local-notifications)
confere "tabela fiapx-local-notifications (PK email)" '"AttributeName": "email"' "$tabela"
confere "sort key message_id" '"AttributeName": "message_id"' "$tabela"
confere "LSI email-created_at-index" email-created_at-index "$tabela"
confere "TTL em expires_at" ENABLED "$(aws_ dynamodb describe-time-to-live --table-name fiapx-local-notifications)"

secao "SES"
confere "remetente nao-responda@hackfiapf5.click" nao-responda@hackfiapf5.click "$(aws_ ses list-identities)"

secao "Secrets Manager"
segredos=$(aws_ secretsmanager list-secrets --query 'SecretList[].Name' --output text | tr '\t' '\n')
lista <<<"$segredos"
for s in fiapx/local/auth/jwt-private-key fiapx/local/db/auth fiapx/local/db/video; do
  confere "segredo $s" "$s" "$segredos"
done

secao "SSM Parameter Store (/fiapx/local)"
params=$(aws_ ssm get-parameters-by-path --path /fiapx/local --recursive --query 'Parameters[].Name' --output text | tr '\t' '\n' | sort)
lista <<<"$params"
for p in s3/videos_bucket sqs/video-uploaded/url sqs/processing-commands/url sqs/saga-replies/url \
         sqs/notification-commands/url aurora/endpoint db/auth/secret_arn db/video/secret_arn \
         auth/jwt_public_key auth/jwt_private_key_secret_arn ses/from_address web/url \
         dynamodb/notifications/table_name; do
  confere "/fiapx/local/$p" "/fiapx/local/$p" "$params"
done

secao "Mailpit"
confere "API do Mailpit respondendo" '"Version"' "$(curl -sf "http://localhost:${MAILPIT_UI_PORT:-8025}/api/v1/info")"

secao "Teste de fumaça"
# 1) Upload em uploads/ gera evento na fila video-uploaded.
url_fila=$(aws_ ssm get-parameter --name /fiapx/local/sqs/video-uploaded/url --query Parameter.Value --output text)
chave="uploads/verificacao-$$.mp4"
echo "fiapx" | aws_ s3 cp - "s3://fiapx-local-videos/${chave}" >/dev/null
# Lê até achar o evento do arquivo de teste (pode haver outras mensagens na fila) e apaga o que leu.
achou=""
for _ in 1 2 3 4 5; do
  msg=$(aws_ sqs receive-message --queue-url "$url_fila" --wait-time-seconds 5 --max-number-of-messages 10)
  [ -z "$msg" ] && continue
  grep -q "$chave" <<<"$msg" && achou=1
  python3 -c "import json,sys; [print(m['ReceiptHandle']) for m in json.loads(sys.argv[1]).get('Messages',[])]" "$msg" |
    while read -r h; do aws_ sqs delete-message --queue-url "$url_fila" --receipt-handle "$h"; done
  [ -n "$achou" ] && break
done
if [ -n "$achou" ]; then ok "upload em uploads/ gerou ObjectCreated na fila video-uploaded"
else falha "upload em uploads/ não gerou evento na fila video-uploaded"; fi
aws_ s3 rm "s3://fiapx-local-videos/${chave}" >/dev/null

# 2) Arquivo fora de uploads/ não gera evento.
echo "fiapx" | aws_ s3 cp - "s3://fiapx-local-videos/results/verificacao-$$/frames.zip" >/dev/null
msg=$(aws_ sqs receive-message --queue-url "$url_fila" --wait-time-seconds 3 --max-number-of-messages 1)
if grep -q "results/verificacao-$$" <<<"$msg"; then falha "results/ não deveria gerar evento"; else ok "results/ não gera evento"; fi
aws_ s3 rm "s3://fiapx-local-videos/results/verificacao-$$/frames.zip" >/dev/null

# 3) E-mail enviado por SMTP chega ao Mailpit.
assunto="verificacao-ambiente-$$"
printf 'From: nao-responda@hackfiapf5.click\nTo: teste@fiapx.local\nSubject: %s\n\nok\n' "$assunto" \
  | docker compose exec -T mailpit /mailpit sendmail -S localhost:1025 -t
busca=$(curl -sf "http://localhost:${MAILPIT_UI_PORT:-8025}/api/v1/search?query=subject:${assunto}")
confere "e-mail SMTP chegou ao Mailpit" "$assunto" "$busca"
id=$(python3 -c "import json,sys; m=json.loads(sys.argv[1] or '{}').get('messages',[]); print(m[0]['ID'] if m else '')" "$busca")
[ -n "$id" ] && curl -sf -X DELETE -H 'Content-Type: application/json' -d "{\"IDs\":[\"$id\"]}" \
  "http://localhost:${MAILPIT_UI_PORT:-8025}/api/v1/messages" >/dev/null

echo
if [ "$FALHAS" -eq 0 ]; then
  printf '\033[32mAmbiente local OK.\033[0m  Mailpit: http://localhost:%s  LocalStack: http://localhost:%s\n' \
    "${MAILPIT_UI_PORT:-8025}" "${LOCALSTACK_PORT:-4566}"
else
  printf '\033[31m%d verificação(ões) falharam.\033[0m\n' "$FALHAS"
  exit 1
fi
