#!/usr/bin/env bash
set -euo pipefail

# Provisiona uma instancia B4G usando templates locais.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_NAME="B4G_Instance_01"
CONTAINER_IMAGE="endevor-bridge-for-git.packages.broadcom.com/bridge-for-git:3.0.0"
PORT="8080"
HOST="localhost"
B4G_URL=""
GIT_SERVER_URL="http://localhost:3033"
GIT_CLIENT_ID=""
GIT_CLIENT_SECRET=""
GIT_PROVIDER="gitea"
GIT_API_URL=""
TARGET_ROOT="/auto"
APPLICATION_TEMPLATE=""
DOCKER_COMPOSE_TEMPLATE="${SKILL_DIR}/assets/docker-compose.template.yml"
CREATE_GITEA_APP="false"
CREATE_GITLAB_APP="false"
GITLAB_TOKEN=""
GITEA_BASIC_AUTH_B64=""
SHOW_LOGS="true"

usage() {
  cat <<'EOF'
Uso:
  provision-b4g.sh [opcoes]

Opcoes:
  --project-name <valor>         Nome da instancia (padrao: B4G_Instance_01)
  --container-image <valor>      Imagem Docker B4G
  --port <valor>                 Porta externa (padrao: 8080)
  --host <valor>                 Host DNS/IP (padrao: localhost)
  --b4g-url <valor>              URL publica B4G (default: http://<host>:<port>)
  --git-provider <valor>         Provedor Git: gitea | github | gitlab (padrao: gitea)
  --git-server-url <valor>       URL do servidor Git
  --git-api-url <valor>          URL da API REST do servidor Git (auto-detectado por provider)
  --git-client-id <valor>        Client ID OAuth
  --git-client-secret <valor>    Client Secret OAuth
  --target-root <valor>          Raiz de provisionamento (padrao: /auto)
  --application-template <path>  Template application.yml (auto por provider se omitido)
  --docker-compose-template <p>  Template docker-compose.yml
  --create-gitea-app             Cria app OAuth no Gitea se ID/Secret nao informados
  --gitea-basic-auth-b64 <valor> Credencial Basic Auth em Base64 (para --create-gitea-app)
  --create-gitlab-app            Cria app OAuth no GitLab se ID/Secret nao informados
  --gitlab-token <valor>         Personal Access Token GitLab com escopo admin (OAuth e verificacao de webhooks)
  --no-logs                      Nao exibir logs ao final
  -h, --help                     Exibe esta ajuda

Exemplos:
  # Gitea (criacao automatica de OAuth app)
  provision-b4g.sh --git-provider gitea --project-name MyB4G --port 8080 \\
    --git-server-url http://gitea:3033 --create-gitea-app --gitea-basic-auth-b64 <base64>

  # GitHub Enterprise Server (credenciais fornecidas manualmente)
  provision-b4g.sh --git-provider github --project-name MyB4G --port 8080 \\
    --git-server-url https://github.example.net --git-client-id <id> --git-client-secret <secret>

  # GitLab (criacao automatica de OAuth app)
  provision-b4g.sh --git-provider gitlab --project-name MyB4G --port 8080 \\
    --git-server-url https://gitlab.example.net --create-gitlab-app --gitlab-token <pat>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --container-image)
      CONTAINER_IMAGE="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --b4g-url)
      B4G_URL="$2"
      shift 2
      ;;
    --git-server-url)
      GIT_SERVER_URL="$2"
      shift 2
      ;;
    --git-client-id)
      GIT_CLIENT_ID="$2"
      shift 2
      ;;
    --git-client-secret)
      GIT_CLIENT_SECRET="$2"
      shift 2
      ;;
    --target-root)
      TARGET_ROOT="$2"
      shift 2
      ;;
    --application-template)
      APPLICATION_TEMPLATE="$2"
      shift 2
      ;;
    --docker-compose-template)
      DOCKER_COMPOSE_TEMPLATE="$2"
      shift 2
      ;;
    --create-gitea-app)
      CREATE_GITEA_APP="true"
      shift
      ;;
    --gitea-basic-auth-b64)
      GITEA_BASIC_AUTH_B64="$2"
      shift 2
      ;;
    --git-provider)
      GIT_PROVIDER="$2"
      shift 2
      ;;
    --git-api-url)
      GIT_API_URL="$2"
      shift 2
      ;;
    --create-gitlab-app)
      CREATE_GITLAB_APP="true"
      shift
      ;;
    --gitlab-token)
      GITLAB_TOKEN="$2"
      shift 2
      ;;
    --no-logs)
      SHOW_LOGS="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Parametro invalido: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${B4G_URL}" ]]; then
  B4G_URL="http://${HOST}:${PORT}"
fi

# Provider-specific defaults
if [[ -z "${APPLICATION_TEMPLATE}" ]]; then
  case "${GIT_PROVIDER}" in
    github) APPLICATION_TEMPLATE="${SKILL_DIR}/assets/application.template.github.yml" ;;
    gitlab) APPLICATION_TEMPLATE="${SKILL_DIR}/assets/application.template.gitlab.yml" ;;
    *)      APPLICATION_TEMPLATE="${SKILL_DIR}/assets/application.template.yml" ;;
  esac
fi
if [[ -z "${GIT_API_URL}" ]]; then
  case "${GIT_PROVIDER}" in
    github) GIT_API_URL="${GIT_SERVER_URL}/api/v3" ;;
    gitlab) GIT_API_URL="${GIT_SERVER_URL}/api/v4" ;;
    *)      GIT_API_URL="${GIT_SERVER_URL}/api/v1" ;;
  esac
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Erro: docker nao encontrado no PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Erro: docker compose nao esta disponivel." >&2
  exit 1
fi

if [[ ! -f "${APPLICATION_TEMPLATE}" ]]; then
  echo "Erro: template application nao encontrado: ${APPLICATION_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${DOCKER_COMPOSE_TEMPLATE}" ]]; then
  echo "Erro: template docker-compose nao encontrado: ${DOCKER_COMPOSE_TEMPLATE}" >&2
  exit 1
fi

INSTANCE_DIR="${TARGET_ROOT}/${PROJECT_NAME}"
WORKDIR_DIR="${INSTANCE_DIR}/workdir"
LOGS_DIR="${WORKDIR_DIR}/logs"
mkdir -p "${LOGS_DIR}"
chmod -R 777 "${INSTANCE_DIR}" 2>/dev/null || true

echo "[1/6] Estrutura criada em ${INSTANCE_DIR}"

create_gitea_app() {
  local payload response
  payload=$(cat <<EOF
{"confidential_client":true,"name":"${PROJECT_NAME}","redirect_uris":["${B4G_URL}/oauth2/callback/gitea"],"skip_secondary_authorization":true}
EOF
)

  response=$(curl -sS -X POST \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic ${GITEA_BASIC_AUTH_B64}" \
    -d "${payload}" \
    "${GIT_SERVER_URL}/api/v1/user/applications/oauth2")

  if command -v jq >/dev/null 2>&1; then
    GIT_CLIENT_ID=$(printf '%s' "${response}" | jq -r '.client_id // empty')
    GIT_CLIENT_SECRET=$(printf '%s' "${response}" | jq -r '.client_secret // empty')
  else
    GIT_CLIENT_ID=$(printf '%s' "${response}" | sed -n 's/.*"client_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    GIT_CLIENT_SECRET=$(printf '%s' "${response}" | sed -n 's/.*"client_secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi

  if [[ -z "${GIT_CLIENT_ID}" || -z "${GIT_CLIENT_SECRET}" ]]; then
    echo "Erro ao criar app OAuth no Gitea. Resposta: ${response}" >&2
    exit 1
  fi
}

create_gitlab_app() {
  local payload response
  payload=$(cat <<EOF
{"name":"${PROJECT_NAME}","redirect_uri":"${B4G_URL}/oauth2/callback/gitlab","scopes":"api read_user read_repository write_repository","confidential":true}
EOF
)
  response=$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GITLAB_TOKEN}" \
    -d "${payload}" \
    "${GIT_SERVER_URL}/api/v4/applications")

  if command -v jq >/dev/null 2>&1; then
    GIT_CLIENT_ID=$(printf '%s' "${response}" | jq -r '.application_id // empty')
    GIT_CLIENT_SECRET=$(printf '%s' "${response}" | jq -r '.secret // empty')
  else
    GIT_CLIENT_ID=$(printf '%s' "${response}" | sed -n 's/.*"application_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    GIT_CLIENT_SECRET=$(printf '%s' "${response}" | sed -n 's/.*"secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi

  if [[ -z "${GIT_CLIENT_ID}" || -z "${GIT_CLIENT_SECRET}" ]]; then
    echo "Erro ao criar app OAuth no GitLab. Resposta: ${response}" >&2
    exit 1
  fi
}

if [[ -z "${GIT_CLIENT_ID}" || -z "${GIT_CLIENT_SECRET}" ]]; then
  case "${GIT_PROVIDER}" in
    gitea)
      if [[ "${CREATE_GITEA_APP}" != "true" ]]; then
        echo "Erro: informe --git-client-id/--git-client-secret ou use --create-gitea-app." >&2
        exit 1
      fi
      if [[ -z "${GITEA_BASIC_AUTH_B64}" ]]; then
        echo "Erro: informe --gitea-basic-auth-b64 ao usar --create-gitea-app." >&2
        exit 1
      fi
      echo "[2/6] Criando aplicacao OAuth no Gitea"
      create_gitea_app
      echo "Client ID gerado: ${GIT_CLIENT_ID}"
      ;;
    gitlab)
      if [[ "${CREATE_GITLAB_APP}" != "true" ]]; then
        echo "Erro: informe --git-client-id/--git-client-secret ou use --create-gitlab-app." >&2
        exit 1
      fi
      if [[ -z "${GITLAB_TOKEN}" ]]; then
        echo "Erro: informe --gitlab-token ao usar --create-gitlab-app." >&2
        exit 1
      fi
      echo "[2/6] Criando aplicacao OAuth no GitLab"
      create_gitlab_app
      echo "Client ID gerado: ${GIT_CLIENT_ID}"
      ;;
    github)
      echo "AVISO: GitHub nao suporta criacao de OAuth App via API." >&2
      echo "       Crie manualmente em: ${GIT_SERVER_URL}/settings/applications/new" >&2
      echo "       Redirect URI: ${B4G_URL}/oauth2/callback/github" >&2
      echo "       Depois informe --git-client-id e --git-client-secret." >&2
      exit 1
      ;;
    *)
      echo "Erro: informe --git-client-id/--git-client-secret para o provider '${GIT_PROVIDER}'." >&2
      exit 1
      ;;
  esac
else
  echo "[2/6] Usando credenciais OAuth informadas"
fi

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_template() {
  local src="$1"
  local dst="$2"
  cp "${src}" "${dst}"

  local esc_port esc_b4g_url esc_git_server esc_git_api esc_image esc_project esc_client_id esc_client_secret
  esc_port=$(escape_sed "${PORT}")
  esc_b4g_url=$(escape_sed "${B4G_URL}")
  esc_git_server=$(escape_sed "${GIT_SERVER_URL}")
  esc_git_api=$(escape_sed "${GIT_API_URL}")
  esc_image=$(escape_sed "${CONTAINER_IMAGE}")
  esc_project=$(escape_sed "${PROJECT_NAME}")
  esc_client_id=$(escape_sed "${GIT_CLIENT_ID}")
  esc_client_secret=$(escape_sed "${GIT_CLIENT_SECRET}")

  sed -i.bak \
    -e 's/${port}/'"${esc_port}"'/g' \
    -e 's/${b4gUrl}/'"${esc_b4g_url}"'/g' \
    -e 's/${gitServerUrl}/'"${esc_git_server}"'/g' \
    -e 's/${gitApiUrl}/'"${esc_git_api}"'/g' \
    -e 's/${containerImage}/'"${esc_image}"'/g' \
    -e 's/${projectName}/'"${esc_project}"'/g' \
    -e 's/${gitClientID}/'"${esc_client_id}"'/g' \
    -e 's/${gitClientSecret}/'"${esc_client_secret}"'/g' \
    "${dst}"

  rm -f "${dst}.bak"
}

render_template "${APPLICATION_TEMPLATE}" "${INSTANCE_DIR}/application.yml"
echo "[3/6] application.yml gerado"

render_template "${DOCKER_COMPOSE_TEMPLATE}" "${INSTANCE_DIR}/docker-compose.yml"
echo "[4/6] docker-compose.yml gerado"

echo "[5/6] Subindo instancia via Docker Compose"
(
  cd "${INSTANCE_DIR}"
  docker compose up -d
)

verify_git_server_hook_settings() {
  echo "[6/6] Verificando se o Git server permite criar webhooks para URL local/privada"
  case "${GIT_PROVIDER}" in
    gitlab)
      verify_gitlab_local_webhooks
      ;;
    *)
      echo "AVISO: verificacao nao foi possivel. O provider '${GIT_PROVIDER}' nao expoe essa configuracao via API neste fluxo."
      ;;
  esac
}

verify_gitlab_local_webhooks() {
  if [[ -z "${GITLAB_TOKEN}" ]]; then
    echo "AVISO: verificacao nao foi possivel. Sem --gitlab-token (admin) nao e possivel ler allow_local_requests_from_web_hooks_and_services."
    echo "       Sem essa opcao habilitada, o GitLab recusa webhooks para URL privada (422 Invalid url given)."
    return 0
  fi

  local tmp http_code body allowed
  tmp=$(mktemp)
  http_code=$(curl -sS -o "${tmp}" -w '%{http_code}' -m 15 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GIT_API_URL}/application/settings" || true)

  if [[ -z "${http_code}" || "${http_code}" == "000" ]]; then
    echo "AVISO: verificacao nao foi possivel (sem conexao com ${GIT_API_URL}/application/settings)."
    rm -f "${tmp}"
    return 0
  fi

  if [[ "${http_code}" != "200" ]]; then
    echo "AVISO: verificacao nao foi possivel (HTTP ${http_code} em ${GIT_API_URL}/application/settings)."
    rm -f "${tmp}"
    return 0
  fi

  body=$(cat "${tmp}")
  rm -f "${tmp}"

  if command -v jq >/dev/null 2>&1; then
    allowed=$(printf '%s' "${body}" | jq -r '.allow_local_requests_from_web_hooks_and_services // empty')
  else
    allowed=$(printf '%s' "${body}" | sed -n 's/.*"allow_local_requests_from_web_hooks_and_services"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
  fi

  if [[ -z "${allowed}" ]]; then
    echo "AVISO: verificacao nao foi possivel (campo allow_local_requests_from_web_hooks_and_services ausente na resposta)."
    return 0
  fi

  if [[ "${allowed}" == "true" ]]; then
    echo "OK: GitLab permite webhooks para URLs locais/privadas (allow_local_requests_from_web_hooks_and_services=true)."
  else
    echo "AVISO: GitLab NAO permite webhooks para URLs locais/privadas (allow_local_requests_from_web_hooks_and_services=false)."
    echo "       O B4G nao conseguira criar hooks se b4gUrl for hostname/IP privado (422 Invalid url given)."
    echo "       Habilite em Admin > Settings > Network > Outbound requests, ou:"
    echo "       gitlab_rails['allow_local_requests_from_web_hooks_and_services'] = true"
  fi
}

verify_git_server_hook_settings

echo "Provisionamento concluido"
echo "Instancia: ${PROJECT_NAME}"
echo "Diretorio: ${INSTANCE_DIR}"
echo "URL: ${B4G_URL}"

if [[ "${SHOW_LOGS}" == "true" ]]; then
  (
    cd "${INSTANCE_DIR}"
    docker compose logs --tail=20
  )
fi
