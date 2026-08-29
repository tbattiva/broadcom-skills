---
name: b4g-provision
description: 'Provisiona uma nova instancia do Endevor Bridge for Git (BFG/B4G) com base em templates YAML e fluxo de pipeline Jenkins. Suporta Gitea, GitHub Enterprise e GitLab como provedores Git. Use quando precisar criar uma nova instancia, gerar OAuth automaticamente (Gitea/GitLab) ou manualmente (GitHub), renderizar application.yml/docker-compose.yml e subir via Docker Compose.'
argument-hint: 'Informe os parametros da instancia: projectName, port, host, b4gUrl, gitProvider (gitea|github|gitlab), gitServerUrl e credenciais OAuth'
user-invocable: true
---

# B4G Provision

Skill para provisionamento de uma nova instancia do Endevor Bridge for Git (BFG/B4G), espelhando o fluxo observado no pipeline Jenkins do workspace com suporte a multiplos provedores Git (Gitea, GitHub Enterprise e GitLab).

## Quando usar

- Criar uma nova instancia B4G com isolamento por diretorio
- Preparar application.yml e docker-compose.yml a partir de templates por provider
- Criar credenciais OAuth automaticamente no Gitea ou GitLab (opcional)
- Criar credenciais OAuth manualmente no GitHub e fornecer ao script
- Subir e validar a instancia com Docker Compose

## Pre-requisitos

- Bash disponivel (Git Bash no Windows ou shell Linux)
- Docker e plugin Docker Compose (`docker compose`)
- `curl` disponivel no PATH; `jq` opcional (melhora parse de respostas JSON)
- Conectividade com o servidor Git (Gitea, GitHub Enterprise ou GitLab)
- Imagem do B4G disponivel no host

## Parametros esperados

- `projectName`: identificador da instancia (sem espacos)
- `containerImage`: imagem do B4G
- `port`: porta externa para publicar o servico
- `host`: host DNS/IP da maquina
- `b4gUrl`: URL publica da instancia (ex.: http://host:8080)
- `gitProvider`: provedor Git — `gitea` (padrao) | `github` | `gitlab`
- `gitServerUrl`: URL do servidor Git
- `gitApiUrl`: URL da API REST (auto-detectada por provider se omitida)
- `gitClientID` e `gitClientSecret`: credenciais OAuth do app Git

## Provedores Git suportados

| Provider | `auth-provider` no application.yml | Criacao automatica de OAuth app |
|---|---|---|
| **Gitea** | `GITEA` | Sim — via `POST /api/v1/user/applications/oauth2` com Basic Auth |
| **GitHub Enterprise Server** | `GITHUB` | Nao — crie manualmente em `Settings > Developer settings > OAuth Apps` |
| **GitHub Enterprise Cloud** | `GITHUB` | Nao — crie manualmente em `github.com > Settings > Developer settings` |
| **GitLab** | `GITLAB` | Sim — via `POST /api/v4/applications` com Personal Access Token (scope `admin`) |

> **Nota GitHub**: O GitHub nao expoe API publica para criar OAuth Apps. O script exibe as instrucoes e o redirect URI correto quando `--git-client-id/--git-client-secret` nao sao informados.

## Fluxo de provisionamento

1. Criar estrutura da instancia com permissao e pastas de trabalho (`workdir` e `workdir/logs`).
2. Criar aplicacao OAuth no servidor Git, se `gitClientID/gitClientSecret` nao forem fornecidos:
   - **Gitea**: criacao automatica via API com `--create-gitea-app`
   - **GitLab**: criacao automatica via API com `--create-gitlab-app`
   - **GitHub**: exibir instrucoes para criacao manual
3. Selecionar template `application.yml` baseado no provider:
   - Gitea: `application.template.yml` (auth-provider: GITEA)
   - GitHub: `application.template.github.yml` (auth-provider: GITHUB)
   - GitLab: `application.template.gitlab.yml` (auth-provider: GITLAB)
4. Renderizar o `application.yml` substituindo placeholders:
   - `${port}`, `${b4gUrl}`, `${gitServerUrl}`, `${gitApiUrl}`
   - `${containerImage}`, `${projectName}`
   - `${gitClientID}`, `${gitClientSecret}`
5. Renderizar o `docker-compose.yml` com os mesmos placeholders.
6. Executar `docker compose up -d` no diretorio da instancia.
7. Exibir URL final e ultimas linhas de log.

## Execucao

Use o script [provision-b4g.sh](./scripts/provision-b4g.sh):

```bash
# Gitea — criacao automatica de app OAuth
./provision-b4g.sh --git-provider gitea \
  --project-name MyB4G --port 8080 \
  --git-server-url http://gitea:3033 \
  --create-gitea-app --gitea-basic-auth-b64 <base64>

# GitHub Enterprise Server — credenciais fornecidas manualmente
./provision-b4g.sh --git-provider github \
  --project-name MyB4G --port 8080 \
  --git-server-url https://github.example.net \
  --git-client-id <id> --git-client-secret <secret>

# GitHub Enterprise Cloud (api-url diferente)
./provision-b4g.sh --git-provider github \
  --project-name MyB4G --port 8080 \
  --git-server-url https://github.com \
  --git-api-url https://api.github.com \
  --git-client-id <id> --git-client-secret <secret>

# GitLab — criacao automatica de app OAuth
./provision-b4g.sh --git-provider gitlab \
  --project-name MyB4G --port 8080 \
  --git-server-url https://gitlab.example.net \
  --create-gitlab-app --gitlab-token <admin-pat>
```

## Recursos

- Script: [scripts/provision-b4g.sh](./scripts/provision-b4g.sh)
- Template Gitea: [assets/application.template.yml](./assets/application.template.yml)
- Template GitHub: [assets/application.template.github.yml](./assets/application.template.github.yml)
- Template GitLab: [assets/application.template.gitlab.yml](./assets/application.template.gitlab.yml)
- Template compose: [assets/docker-compose.template.yml](./assets/docker-compose.template.yml)

## Observacoes

- Para Gitea: use `--create-gitea-app` com `--gitea-basic-auth-b64` (credencial Basic Auth em Base64).
- Para GitLab: use `--create-gitlab-app` com `--gitlab-token` (PAT com scope `admin:application`).
- Para GitHub Enterprise Cloud, o `--git-api-url` deve ser `https://api.github.com` (diferente da URL da instancia).
- Providers suportados pela documentacao oficial B4G v3.0: `GITEA`, `GITHUB`, `GITLAB`, `AZURE`, `BITBUCKET`, `BITBUCKET_CLOUD`, `LOCAL`.

## Problemas conhecidos

### GitLab: `The requested scope is invalid, unknown, or malformed`

**Sintoma:** em **Sign in with GitLab** o browser vai para `/oauth/authorize` e o GitLab responde:

`An error has occurred. The requested scope is invalid, unknown, or malformed.`

A URL de authorize inclui um `scope` como:

`api read_user read_repository write_repository`

**Causa:** o B4G 3.0 pede esses quatro scopes no authorize. O GitLab so aceita scopes que estao registrados no OAuth Application. Se o app foi criado so com `api read_user`, os extras (`read_repository`, `write_repository`) fazem o authorize falhar — mesmo o scope `api` ja cobrindo acesso a repositorio.

**Prevencao:** ao criar o app (script `--create-gitlab-app` ou criacao manual em Admin > Applications), use exatamente:

`api read_user read_repository write_repository`

O payload de `create_gitlab_app` em [scripts/provision-b4g.sh](./scripts/provision-b4g.sh) ja envia esses scopes.

**Correcao em app ja criado:** atualize os scopes do application no GitLab (Admin area > Applications, ou Rails):

```ruby
app = Authn::OauthApplication.find_by(uid: "<client_id>")
app.scopes = "api read_user read_repository write_repository"
app.save!
```

Nao e necessario recriar o client secret nem reiniciar o B4G. Repita **Sign in with GitLab**.

### `server.port` vs porta publicada no Compose

O `docker-compose` publica `${port}:8080`. O Tomcat dentro do container deve escutar em **8080**. Os templates usam `server.port: 8080` (nao `${port}`). Se `server.port` for igual a porta do host (ex.: 8090), o compose encaminha para uma porta vazia e o browser nao abre o B4G.