---
name: ambiente-local
description: Subir, verificar, depurar e estender o ambiente local do FIAP X (docker compose com MySQL 8.0, LocalStack 4.14.0 e Mailpit em fiapx-infra/local). Use ao rodar serviços localmente, quando algo do ambiente falhar ou ao adicionar um recurso AWS local.
---

# Ambiente local

```bash
cd local
docker compose up -d --wait   # espera os healthchecks, inclusive o fim dos scripts de init
./scripts/verificar.sh        # lista e confere tudo; sai com 1 se algo faltar
docker compose down -v        # derruba e apaga o volume do MySQL
```

## Como funciona

- `init/mysql/01-create-databases.sh` roda `sql/create-databases.sql` **só na primeira subida do volume**.
  Mudou o SQL? `docker compose down -v` e suba de novo.
- `init/localstack/01-recursos.sh` roda a cada subida (o LocalStack Community não guarda estado) e cria
  bucket, filas e DLQs, notificação S3 → SQS, tabela, SES, segredos, chave RSA do JWT e os parâmetros em
  `/fiapx/local/...`. Na última linha ele cria `/tmp/fiapx-init-ok`; o healthcheck do container depende
  desse arquivo. Se o script falhar, o container nunca fica saudável.
- Logs do init: `docker compose logs localstack | grep -E "fiapx-init|ERROR"`.

## Armadilhas conhecidas

- **Versão do LocalStack:** fixada em `4.14.0`. As `2026.x` encerram sem `LOCALSTACK_AUTH_TOKEN`.
- **AWS CLI v1 e URLs:** valores que começam com `http://` são baixados como URL; o init roda
  `aws configure set cli_follow_urlparam false`.
- **`s3:TestEvent`:** configurar a notificação manda uma mensagem de teste para a `video-uploaded`; o init
  limpa a fila.
- **Host do banco nos segredos:** `localhost`. Um serviço dentro do compose usa `mysql`.
- No macOS, `head` pode ser o `lwp-request`: use `/usr/bin/head`. Não há `timeout`: use laços com `sleep`.

## Adicionar um recurso

1. Crie no `init/localstack/01-recursos.sh` com o prefixo `fiapx-${ENV}-` e publique a chave no SSM
   (skill `parametro-ssm`).
2. Acrescente a conferência no `scripts/verificar.sh`.
3. Atualize a tabela "Recursos criados" do README e, no `fiapx-docs`, `06-deploy/parametros-ssm.md`.
4. Valide: `shellcheck -x` nos scripts (ou `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 -x ...`),
   `docker compose down -v && docker compose up -d --wait && ./scripts/verificar.sh`.
5. O workflow `ambiente-local` repete isso no PR.
