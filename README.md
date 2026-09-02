# Broadcom Skills

Este repositorio contem uma skill para provisionamento de novas instancias do Endevor Bridge for Git (BFG/B4G), baseada no fluxo existente do pipeline Jenkins e nos templates YAML do workspace.

## Skill Disponivel

- Nome: `b4g-provision`
- Local: `.github/skills/b4g-provision`
- Objetivo: criar diretorio da instancia, preparar `application.yml` e `docker-compose.yml`, opcionalmente criar app OAuth no Gitea e subir a instancia com Docker Compose.

## Fontes Utilizadas para o Fluxo

A skill foi modelada a partir dos seguintes arquivos do workspace:

- `b4g_provision.jenkinsfile`
- `application.yml`
- `docker-compose.yml`

## Estrutura da Skill

- `.github/skills/b4g-provision/SKILL.md`
- `.github/skills/b4g-provision/scripts/provision-b4g.sh`
- `.github/skills/b4g-provision/assets/application.template.yml`
- `.github/skills/b4g-provision/assets/docker-compose.template.yml`

## Como Executar o Provisionamento

O script e compativel com Linux e Windows via Git Bash.

1. Garanta Docker e Docker Compose instalados e ativos.
2. Dê permissao de execucao ao script (Linux/Git Bash):

   ```bash
   chmod +x .github/skills/b4g-provision/scripts/provision-b4g.sh
   ```

3. Execute com credenciais OAuth ja existentes:

   ```bash
   .github/skills/b4g-provision/scripts/provision-b4g.sh \
     --project-name B4G_Instance_01 \
     --container-image endevor-bridge-for-git.packages.broadcom.com/bridge-for-git:3.0.0 \
     --port 8080 \
     --host tf896250-ubuntu22-dev01.msd.labs.broadcom.net \
     --b4g-url http://tf896250-ubuntu22-dev01.msd.labs.broadcom.net:8080 \
     --git-server-url http://tf896250-ubuntu22-dev01.msd.labs.broadcom.net:3033 \
     --git-client-id <client_id> \
     --git-client-secret <client_secret>
   ```

4. Ou execute com criacao automatica de app OAuth no Gitea:

   ```bash
   .github/skills/b4g-provision/scripts/provision-b4g.sh \
     --project-name B4G_Instance_01 \
     --container-image endevor-bridge-for-git.packages.broadcom.com/bridge-for-git:3.0.0 \
     --port 8080 \
     --host tf896250-ubuntu22-dev01.msd.labs.broadcom.net \
     --b4g-url http://tf896250-ubuntu22-dev01.msd.labs.broadcom.net:8080 \
     --git-server-url http://tf896250-ubuntu22-dev01.msd.labs.broadcom.net:3033 \
     --create-gitea-app \
     --gitea-basic-auth-b64 <base64_usuario_senha>
   ```

## O Que o Script Faz

1. Cria estrutura em `/auto/<projectName>` com `workdir` e `workdir/logs`.
2. Cria app OAuth no Gitea (quando solicitado).
3. Renderiza placeholders nos templates:
   - `${port}`
   - `${b4gUrl}`
   - `${gitServerUrl}`
   - `${containerImage}`
   - `${projectName}`
   - `${gitClientID}`
   - `${gitClientSecret}`
4. Ajusta a porta do `application.yml`.
5. Executa `docker compose up -d`.
6. Verifica se o Git server permite webhooks para URL local/privada (GitLab: `allow_local_requests_from_web_hooks_and_services`). Se nao for possivel consultar, avisa o usuario.
7. Exibe URL final e logs (ultimas 20 linhas por padrao).

## Observacoes

- Diretorio de provisionamento padrao: `/auto`.
- Para mudar a raiz, utilize `--target-root`.
- Para ocultar logs ao final, utilize `--no-logs`.
