# fiapx-infra

Infraestrutura do FIAP X: VPC, EKS (add-ons), Aurora MySQL, S3, SQS/DLQ, SES, ECR, API Gateway + VPC Link + ALB interno, Secrets, OIDC do GitHub, outputs no SSM e ambiente local (docker-compose + LocalStack).

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

Os módulos Terraform da AWS (`bootstrap/`, `modules/`, `envs/prod/`) chegam na Etapa 7.

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
| LocalStack (S3, SQS, SES, SSM, Secrets Manager, DynamoDB, Lambda, API Gateway, IAM) | `http://localhost:4566` | `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, região `us-east-1` |
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
| Remetente SES e configuration set | `nao-responda@hackfiapf5.click`, `fiapx-local` | `/ses/from_address`, `/ses/configuration_set` |
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
