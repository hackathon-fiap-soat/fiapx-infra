# fiapx-infra

Infraestrutura do FIAP X: VPC, EKS (add-ons), Aurora MySQL, S3 (vídeos), SQS/DLQ, ECR, API Gateway + VPC Link + ALB interno, Secrets, outputs no SSM, orquestração do deploy (`deploy-all`/`destroy-all`) e ambiente local (docker-compose + LocalStack).

> Parte do **Hackathon FIAP X — Processador de Vídeos** (PÓS TECH SOAT, Fase 5).
> 🚧 Em construção. A documentação vem antes do código: a arquitetura, as decisões (ADRs/RFCs) e os
> contratos ficam em [`fiapx-docs`](https://github.com/hackathon-fiap-soat/fiapx-docs).

## Stack

Terraform + Helm + docker-compose + LocalStack 4.14.0 + MySQL 8.0 + Mailpit

## Estrutura

```text
local/                     ambiente local (Etapa 2)
├── docker-compose.yml     MySQL 8.0, LocalStack 4.14.0 e Mailpit
├── .env.example           valores padrão (só para uso local)
├── init/mysql/            roda sql/create-databases.sql na primeira subida do MySQL
├── init/localstack/       cria bucket, filas, DLQs, tabela, segredos e parâmetros SSM
└── scripts/verificar.sh   lista e confere os recursos, com teste de fumaça
sql/create-databases.sql   databases fiapx_auth e fiapx_video e usuários com privilégio mínimo (entregável)
```

Infraestrutura da AWS (Etapa 7), na conta da **AWS Academy Learner Lab**
([ADR-019](https://github.com/hackathon-fiap-soat/fiapx-docs/blob/main/04-adrs/ADR-019-deploy-na-aws-academy-learner-lab.md)):

```text
envs/prod/                 raiz: liga os módulos, cria os databases (databases.tf) e publica o SSM
modules/network/           VPC 2 AZs, NAT único, endpoints gateway (S3, DynamoDB), SG das Lambdas
modules/eks/               cluster e node group on-demand t3.large (2–4) com a LabRole; IMDS com 2 saltos
modules/eks-addons/        Helm: AWS Load Balancer Controller, metrics-server, KEDA e New Relic (se houver key)
modules/aurora/            Aurora MySQL 8.0 db.t3.medium (o lab nega Serverless v2), segredos do master e de cada serviço
modules/s3-bucket/         cria/apaga o bucket pelo AWS CLI (a SCP do lab nega uma leitura do aws_s3_bucket)
modules/storage/           bucket de vídeos: BPA, SSE-S3, CORS do POST, lifecycle, ObjectCreated → SQS
modules/messaging/         video-uploaded, processing-commands, saga-replies.fifo + DLQs, alarmes e tópico SNS
modules/ecr/               fiapx-video-api, fiapx-video-processor e fiapx-web (scan on push, 10 imagens)
modules/edge/              HTTP API (rate limit, logs), VPC Link, ALB interno; target groups do video-api (/api/*) e do site (padrão)
modules/jwt/               par RSA do JWT: privada no Secrets Manager, pública no SSM
modules/ssm-outputs/       /fiapx/<env>/... (catálogo em fiapx-docs/06-deploy/parametros-ssm.md)
.github/actions/aws-lab/   credenciais do lab (Secrets) + bucket do state; usada por todos os repositórios
.github/workflows/         terraform.yml, deploy-all.yml, destroy-all.yml, local.yml
```

## Deploy na AWS (AWS Academy)

Todo `apply`/`destroy` é feito pelo GitHub Actions, sem passo manual na AWS (ADR-016, ADR-019).

1. **Antes de cada deploy:** iniciar a sessão do lab e copiar as credenciais de *AWS Details* para os Secrets
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` (da organização ou de cada repositório).
   **Nunca em Variables:** os repositórios são públicos e Variables aparecem nos logs. As credenciais
   expiram com a sessão (~4 h); um job com credencial vencida falha avisando.
2. **Secrets opcionais:** `NEW_RELIC_LICENSE_KEY` (instala o `nri-bundle` e liga o APM) e `ALERT_EMAILS`
   (JSON, ex.: `["time@exemplo.com"]`, assinaturas de e-mail dos alarmes das DLQs). Variable opcional
   `AURORA_INSTANCE_CLASS` (padrão `db.t3.medium`; o lab nega `db.serverless`).
3. **Automático:** todo merge no `fiapx-infra` que muda a infraestrutura roda o `apply` e, se der certo, dispara
   sozinho o `deploy-all` a partir da notification. Merges nos serviços fazem o deploy de cada um.
   **Subir tudo manualmente:** *Actions → deploy-all → Run workflow*, `confirm = deploy-prod`. Ordem: infra →
   notification → auth → video-api, com o processor em paralelo → smoke (health, cadastro, login, lista
   autenticada, 401 sem token e um vídeo de 3 s até `COMPLETED` com o zip de 3 frames).
   `a_partir_de` retoma uma subida que falhou no meio. O site entra quando existir (Etapa 6.5).
4. **Derrubar tudo:** *Actions → destroy-all*, `confirm = destroy-prod`. Fazer ao fim de cada demonstração:
   o ambiente custa ~US$ 10/dia do crédito do lab.

`terraform.yml`: em PR, `fmt`, `validate` e `plan` comentado no PR; no merge na `main`, `apply` (primeiro
rede e EKS, depois o resto). O state fica no bucket `fiapx-tfstate-<account_id>` (criado pela action
`aws-lab` se faltar), chave `fiapx-infra/prod.tfstate`, com lock nativo do S3.

**Site:** o Block Public Access da conta impede S3 static website. O site é um pod nginx do `fiapx-web` no
EKS: o ALB manda `/api/*` para o video-api e o resto para o site, e o `fiapx-web` cria a rota `$default` do
API Gateway. Site e API ficam na mesma origem (a URL do API Gateway, em HTTPS), sem CORS (ADR-019).

**Restrições do lab encontradas no primeiro `apply`:** SCP nega `s3:GetBucketObjectLockConfiguration` (por
isso os buckets são criados pelo AWS CLI no módulo `s3-bucket`); `db.serverless` negado; descrições de
security group só em ASCII.

## Como rodar o ambiente local

Pré-requisito: Docker com Compose v2. Não precisa de conta na AWS nem de AWS CLI.

```bash
cd local
docker compose up -d --wait   # sobe tudo e espera os scripts de init terminarem (~30 s)
./scripts/verificar.sh        # lista os recursos e roda o teste de fumaça; sai com 1 se algo faltar
docker compose down -v        # derruba e apaga os dados do MySQL
```

| Serviço | Endereço | Credenciais |
|---|---|---|
| MySQL 8.0 (no lugar do Aurora) | `localhost:3306` | `fiapx_auth` / `fiapx_auth_local`, `fiapx_video` / `fiapx_video_local`, `root` / `root_local` |
| LocalStack (S3, SQS, SSM, Secrets Manager, DynamoDB, Lambda, API Gateway, IAM) | `http://localhost:4566` | `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, região `us-east-1` |
| Mailpit (caixa de entrada) | UI em `http://localhost:8025`, SMTP em `localhost:1025` | sem autenticação |

Os valores são só para uso local. Para trocar portas ou senhas, copie `local/.env.example` para `local/.env`.

Para apontar um serviço para o LocalStack, basta `AWS_ENDPOINT_URL=http://localhost:4566` com as
credenciais `test`: os SDKs da AWS (PHP e Node.js) leem essa variável. Os nomes dos recursos vêm do SSM,
como em produção.

### Recursos criados

Mesmos nomes de produção, com o prefixo `fiapx-local-*` e os parâmetros em `/fiapx/local/...`
([ADR-001](https://github.com/hackathon-fiap-soat/fiapx-docs/blob/main/04-adrs/ADR-001-polyrepo-e-integracao-via-ssm-parameter-store.md)).

| Recurso | Nome | Parâmetro SSM |
|---|---|---|
| Bucket de vídeos (Block Public Access, SSE-S3, CORS só `POST` da origem do front, lifecycle `uploads/` 7 dias e `results/` 30 dias) | `fiapx-local-videos` | `/s3/videos_bucket` |
| Notificação `ObjectCreated` em `uploads/` | bucket → `fiapx-local-video-uploaded` | — |
| Fila Standard, visibility 60 s, DLQ após 5 | `fiapx-local-video-uploaded` | `/sqs/video-uploaded/url`, `/arn` |
| Fila Standard, visibility 300 s, DLQ após 3 | `fiapx-local-processing-commands` | `/sqs/processing-commands/url`, `/arn` |
| Fila FIFO, visibility 60 s, DLQ após 3 | `fiapx-local-saga-replies.fifo` | `/sqs/saga-replies/url`, `/arn` |
| Fila Standard, visibility 60 s, DLQ após 3 (*) | `fiapx-local-notification-commands` | `/sqs/notification-commands/url`, `/arn` |
| DLQs (retenção de 14 dias) | `fiapx-local-<fila>-dlq[.fifo]` | `/sqs/<fila>-dlq/url` |
| Tabela DynamoDB (PK `email`, SK `message_id`, LSI `email-created_at-index`, TTL `expires_at`) (*) | `fiapx-local-notifications` | `/dynamodb/notifications/table_name` |
| SMTP do Mailpit (mesmas chaves que o provedor externo em produção) e remetente | `mailpit:1025`, segredo `fiapx/local/notification/smtp` (`from` = `nao-responda@fiapx.local`) | `/notification/smtp_host`, `/smtp_port`, `/smtp_secret_arn` |
| Chave privada RSA do JWT (gerada a cada subida) | segredo `fiapx/local/auth/jwt-private-key` | `/auth/jwt_private_key_secret_arn` |
| Chave pública do JWT | — | `/auth/jwt_public_key` |
| Usuários do banco (`host`, `port`, `username`, `password`, `dbname`) | segredos `fiapx/local/db/auth` e `fiapx/local/db/video` | `/db/auth/secret_arn`, `/db/video/secret_arn` |
| MySQL | `localhost:3306` | `/aurora/endpoint`, `/aurora/port` |
| Front-end | `http://localhost:5173` | `/web/url` |

(*) Em produção, a fila `notification-commands` e a tabela são criadas pelo Terraform do
`fiapx-notification`. Localmente, o init cria tudo para o ambiente subir com um único comando.

### Observações

- **Versão do LocalStack:** fixada em `4.14.0`, a última Community que roda sem `LOCALSTACK_AUTH_TOKEN`
  (as versões `2026.x` exigem conta).
- **Sem persistência no LocalStack:** filas, bucket, segredos e a chave do JWT são recriados a cada subida.
  O MySQL guarda os dados no volume `mysql-data` até o `down -v`.
- **`s3:TestEvent`:** ao configurar a notificação, o S3 envia uma mensagem de teste para a fila. O init
  limpa a fila, mas o consumidor do `fiapx-video-api` deve ignorar essa mensagem, porque em produção ela
  também chega.
- **Containers de outros repositórios:** entram na rede `fiapx_default` (ex.: o compose do `fiapx-video-api`) e
  usam os hosts `mysql` e `localstack`. As URLs que o LocalStack devolve, como as das filas
  (`sqs.us-east-1.localhost.localstack.cloud`), também funcionam ali, porque o compose dá esses nomes como alias
  ao container do LocalStack.
- **Host do banco nos segredos:** `localhost`, para quem roda o serviço na máquina. Um serviço dentro do
  compose usa o host `mysql`.

## Script de criação do banco

`sql/create-databases.sql` é o mesmo nos dois ambientes. Ele cria os databases `fiapx_auth` e
`fiapx_video` e um usuário por serviço, com acesso só ao próprio database (DML para a aplicação e DDL
para as migrations). As senhas não ficam no arquivo: são passadas por variável de sessão
(`@fiapx_auth_password`, `@fiapx_video_password`). As tabelas são criadas pelas migrations de cada
serviço.

## CI

O workflow `ambiente-local` roda em todo PR que altera `local/` ou `sql/`: `shellcheck` nos scripts e
`docker compose up --wait` seguido de `./scripts/verificar.sh`.

## Links

- Documentação: [`fiapx-docs`](https://github.com/hackathon-fiap-soat/fiapx-docs)
- Todos os repositórios: [hackathon-fiap-soat](https://github.com/hackathon-fiap-soat)

## Contribuição

- A branch `main` é protegida: toda mudança entra por Pull Request (a aprovação é opcional; qualquer integrante, inclusive o autor, pode fazer o merge).
- O `README.md` deve estar sempre atualizado: toda mudança que afete propósito, stack, como rodar/testar,
  variáveis de ambiente ou links atualiza este arquivo no mesmo PR.
- Nunca commitar segredos (`.env`, chaves, tokens). Use `.env.example` com valores fictícios.
- Contexto para o Claude Code: [`CLAUDE.md`](CLAUDE.md) (projeto, regras e o papel deste repositório) e skills em
  [`.claude/skills/`](.claude/skills/) com os procedimentos deste repositório.

## Licença

[MIT](LICENSE)
