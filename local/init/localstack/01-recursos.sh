#!/bin/bash
# Executado pelo LocalStack quando fica pronto (/etc/localstack/init/ready.d).
# Cria os mesmos recursos de produção com o prefixo fiapx-local-* e publica os nomes no SSM em
# /fiapx/local/..., para que o código dos serviços seja igual nos dois ambientes (ADR-001).
#
# O LocalStack Community não guarda estado: tudo é recriado a cada `docker compose up`.
set -euo pipefail

ENV="${FIAPX_ENV:-local}"
P="fiapx-${ENV}"                      # prefixo dos recursos
SSM="/fiapx/${ENV}"                   # prefixo dos parâmetros
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
WEB_URL="${FIAPX_WEB_URL:-http://localhost:5173}"
FROM_ADDRESS="${FIAPX_SMTP_FROM:-nao-responda@fiapx.local}"
DB_HOST="${FIAPX_DB_HOST:-localhost}"
DB_PORT="${FIAPX_DB_PORT:-3306}"
BUCKET="${P}-videos"

log() { echo "fiapx-init: $*"; }
rm -f /tmp/fiapx-init-ok
# Sem isto, o AWS CLI v1 tenta baixar valores que começam com http:// (ex.: URL das filas no SSM).
aws configure set cli_follow_urlparam false
json() { python3 -c "import json,sys; print(json.dumps($1))"; }
put_param() { awslocal ssm put-parameter --name "$1" --value "$2" --type "${3:-String}" --overwrite >/dev/null; }

# --- S3: bucket de vídeos -----------------------------------------------------------------------
log "bucket ${BUCKET}"
awslocal s3api create-bucket --bucket "$BUCKET" >/dev/null
awslocal s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
awslocal s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
# CORS só para o POST de upload, só a origem do front-end.
awslocal s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration "$(json "{
  'CORSRules': [{'AllowedOrigins': ['${WEB_URL}'], 'AllowedMethods': ['POST'],
                 'AllowedHeaders': ['*'], 'ExposeHeaders': ['ETag'], 'MaxAgeSeconds': 3000}]}")"
awslocal s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration '{
  "Rules": [
    {"ID": "expira-uploads", "Status": "Enabled", "Filter": {"Prefix": "uploads/"}, "Expiration": {"Days": 7}},
    {"ID": "expira-results", "Status": "Enabled", "Filter": {"Prefix": "results/"}, "Expiration": {"Days": 30}}
  ]}'

# --- SQS: filas e DLQs --------------------------------------------------------------------------
# cria_fila <nome> <visibility> <maxReceiveCount> [fifo]
cria_fila() {
  local nome="$1" vis="$2" max="$3" fifo="${4:-}" sufixo="" attrs_dlq="{}" dlq_url dlq_arn url
  if [ -n "$fifo" ]; then
    sufixo=".fifo"
    attrs_dlq='{"FifoQueue":"true"}'
  fi
  dlq_url=$(awslocal sqs create-queue --queue-name "${P}-${nome}-dlq${sufixo}" \
    --attributes "$attrs_dlq" --query QueueUrl --output text)
  awslocal sqs set-queue-attributes --queue-url "$dlq_url" --attributes MessageRetentionPeriod=1209600
  dlq_arn=$(awslocal sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names QueueArn \
    --query Attributes.QueueArn --output text)

  local attrs
  attrs=$(json "{
    'VisibilityTimeout': '${vis}',
    'ReceiveMessageWaitTimeSeconds': '20',
    'MessageRetentionPeriod': '345600',
    'RedrivePolicy': json.dumps({'deadLetterTargetArn': '${dlq_arn}', 'maxReceiveCount': ${max}}),
    **({'FifoQueue': 'true', 'ContentBasedDeduplication': 'false'} if '${fifo}' else {})}")
  url=$(awslocal sqs create-queue --queue-name "${P}-${nome}${sufixo}" --attributes "$attrs" \
    --query QueueUrl --output text)

  local chave="${nome}"
  put_param "${SSM}/sqs/${chave}/url" "$url"
  put_param "${SSM}/sqs/${chave}/arn" \
    "$(awslocal sqs get-queue-attributes --queue-url "$url" --attribute-names QueueArn --query Attributes.QueueArn --output text)"
  put_param "${SSM}/sqs/${chave}-dlq/url" "$dlq_url"
  log "fila ${P}-${nome}${sufixo} (visibility ${vis}s, DLQ após ${max} recebimentos)"
}

cria_fila video-uploaded        60  5
cria_fila processing-commands   300 3
cria_fila saga-replies          60  3 fifo
# Em produção, esta fila é criada pelo Terraform do fiapx-notification. Aqui ela é criada junto
# para o ambiente local ficar completo com um único `docker compose up`.
cria_fila notification-commands 60  3

# --- S3 -> SQS: ObjectCreated em uploads/ ---------------------------------------------------------
VIDEO_UPLOADED_ARN=$(awslocal ssm get-parameter --name "${SSM}/sqs/video-uploaded/arn" --query Parameter.Value --output text)
VIDEO_UPLOADED_URL=$(awslocal ssm get-parameter --name "${SSM}/sqs/video-uploaded/url" --query Parameter.Value --output text)
awslocal sqs set-queue-attributes --queue-url "$VIDEO_UPLOADED_URL" --attributes "$(json "{'Policy': json.dumps({
  'Version': '2012-10-17',
  'Statement': [{'Effect': 'Allow', 'Principal': {'Service': 's3.amazonaws.com'}, 'Action': 'sqs:SendMessage',
                 'Resource': '${VIDEO_UPLOADED_ARN}',
                 'Condition': {'ArnEquals': {'aws:SourceArn': 'arn:aws:s3:::${BUCKET}'}}}]})}")"
awslocal s3api put-bucket-notification-configuration --bucket "$BUCKET" --notification-configuration "$(json "{
  'QueueConfigurations': [{'Id': 'uploads-para-video-uploaded', 'QueueArn': '${VIDEO_UPLOADED_ARN}',
    'Events': ['s3:ObjectCreated:*'],
    'Filter': {'Key': {'FilterRules': [{'Name': 'prefix', 'Value': 'uploads/'}]}}}]}")"
# O S3 manda um s3:TestEvent ao configurar a notificação. O consumidor precisa ignorá-lo de qualquer
# forma (em produção ele também chega), mas aqui a fila começa limpa.
awslocal sqs purge-queue --queue-url "$VIDEO_UPLOADED_URL"
log "notificação S3 uploads/ -> ${P}-video-uploaded"

# --- DynamoDB: histórico de notificações (dono: fiapx-notification) -----------------------------
TABELA="${P}-notifications"
awslocal dynamodb create-table --table-name "$TABELA" --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=email,AttributeType=S AttributeName=message_id,AttributeType=S \
                          AttributeName=created_at,AttributeType=S \
  --key-schema AttributeName=email,KeyType=HASH AttributeName=message_id,KeyType=RANGE \
  --local-secondary-indexes '[{"IndexName":"email-created_at-index",
      "KeySchema":[{"AttributeName":"email","KeyType":"HASH"},{"AttributeName":"created_at","KeyType":"RANGE"}],
      "Projection":{"ProjectionType":"ALL"}}]' >/dev/null
awslocal dynamodb wait table-exists --table-name "$TABELA"
awslocal dynamodb update-time-to-live --table-name "$TABELA" \
  --time-to-live-specification Enabled=true,AttributeName=expires_at >/dev/null
put_param "${SSM}/dynamodb/notifications/table_name" "$TABELA"
log "tabela ${TABELA}"

# --- E-mail: SMTP do Mailpit --------------------------------------------------------------------
# Em produção o fiapx-notification envia por um provedor SMTP externo (ADR-019: o SES é negado na AWS
# Academy). Aqui as mesmas chaves apontam para o Mailpit, sem autenticação.
SMTP_SECRET_ARN=$(awslocal secretsmanager create-secret --name "fiapx/${ENV}/notification/smtp" \
  --secret-string "$(json "{'user': '', 'password': '', 'from': '${FROM_ADDRESS}'}")" --query ARN --output text)
put_param "${SSM}/notification/smtp_host" "mailpit"
put_param "${SSM}/notification/smtp_port" "1025"
put_param "${SSM}/notification/smtp_secret_arn" "$SMTP_SECRET_ARN"
log "SMTP mailpit:1025, remetente ${FROM_ADDRESS}"

# --- Secrets Manager: chave do JWT e usuários do banco ---------------------------------------------
# Par de chaves RSA gerado a cada subida: nenhuma chave fica versionada. A privada vai para o
# Secrets Manager (só a Lambda login/password lê) e a pública para o SSM (authorizer e video-api).
TMP=$(mktemp -d)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/jwt.pem" 2>/dev/null
openssl pkey -in "$TMP/jwt.pem" -pubout -out "$TMP/jwt.pub" 2>/dev/null
JWT_SECRET_ARN=$(awslocal secretsmanager create-secret --name "fiapx/${ENV}/auth/jwt-private-key" \
  --secret-string "file://$TMP/jwt.pem" --query ARN --output text)
put_param "${SSM}/auth/jwt_private_key_secret_arn" "$JWT_SECRET_ARN"
put_param "${SSM}/auth/jwt_public_key" "$(cat "$TMP/jwt.pub")"
rm -rf "$TMP"
log "chave RSA do JWT (privada no Secrets Manager, pública no SSM)"

cria_segredo_db() {
  local servico="$1" senha="$2" valor arn
  valor=$(python3 -c "import json,sys; print(json.dumps({'engine':'mysql','host':sys.argv[1],'port':int(sys.argv[2]),
    'username':'fiapx_'+sys.argv[3],'password':sys.argv[4],'dbname':'fiapx_'+sys.argv[3]}))" \
    "$DB_HOST" "$DB_PORT" "$servico" "$senha")
  arn=$(awslocal secretsmanager create-secret --name "fiapx/${ENV}/db/${servico}" --secret-string "$valor" \
    --query ARN --output text)
  put_param "${SSM}/db/${servico}/secret_arn" "$arn"
}
cria_segredo_db auth  "${FIAPX_AUTH_DB_PASSWORD:?}"
cria_segredo_db video "${FIAPX_VIDEO_DB_PASSWORD:?}"
put_param "${SSM}/aurora/endpoint" "$DB_HOST"
put_param "${SSM}/aurora/port" "$DB_PORT"
log "segredos dos usuários fiapx_auth e fiapx_video"

# --- Demais parâmetros ------------------------------------------------------------------------------
put_param "${SSM}/s3/videos_bucket" "$BUCKET"
put_param "${SSM}/web/url" "$WEB_URL"
put_param "${SSM}/region" "$REGION"

log "pronto: $(awslocal ssm get-parameters-by-path --path "$SSM" --recursive --query 'Parameters[].Name' --output text | wc -w | tr -d ' ') parâmetros em ${SSM}/"
touch /tmp/fiapx-init-ok
