---
name: parametro-ssm
description: Convenção para criar, mudar ou ler chaves do SSM Parameter Store (/fiapx/<env>/...) e segredos do Secrets Manager que ligam os repositórios fiapx-*. Use ao expor um recurso para outro repositório.
---

# Parâmetros SSM e segredos

A integração entre repositórios é só pelo SSM (ADR-001): nada de `terraform_remote_state`.

- Prefixo `/fiapx/<env>/`, com `<env>` = `prod` (AWS) ou `local` (LocalStack). Mesmas chaves nos dois.
- Nome: `<serviço-ou-recurso>/<atributo>` em minúsculas (`sqs/video-uploaded/url`, `db/auth/secret_arn`).
- Valor sensível vai para o **Secrets Manager** (`fiapx/<env>/...`); o SSM guarda só o ARN do segredo.
- Catálogo oficial: `fiapx-docs/06-deploy/parametros-ssm.md` (quem publica e quem lê cada chave).

## Criar ou mudar uma chave

1. Atualize o catálogo no `fiapx-docs` (PR lá primeiro ou junto).
2. Publique a chave:
   - na AWS, pelo módulo `ssm-outputs` deste repositório (ou pelo Terraform do repositório dono do recurso,
     como a fila `notification-commands`);
   - no ambiente local, com `put_param` no `local/init/localstack/01-recursos.sh`.
3. Inclua a chave na lista do `local/scripts/verificar.sh`.
4. **Renomear quebra quem lê** e o Terraform não detecta entre repositórios: crie a nova, migre os leitores,
   e só depois remova a antiga.
