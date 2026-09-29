#!/usr/bin/env bash
# Validate the root .env against the requirements documented in DEPLOYMENT.md.
#
# Reports every problem it finds in one pass instead of stopping at the first
# one, so a half-configured file can be fixed in a single round trip. Warnings
# describe values that work but are likely to bite later (weak secrets, an empty
# tunnel token, disabled email delivery).
#
# Used directly (`make check`) and by deploy.sh, update.sh and status.sh.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Read-only validation: neither --dry-run nor --yes means anything here.
COMMON_OPTS=()

QUIET=0

usage() {
  print_help \
    "Validate ${ENV_FILE} against the requirements in DEPLOYMENT.md." \
    "scripts/check-env.sh [--quiet]" \
    "--quiet               print nothing when the file is valid" \
    "--env-file PATH       validate PATH instead of ${ENV_FILE}"
}

while (( $# )); do
  case "$1" in
    --quiet) QUIET=1 ;;
    --env-file)
      shift
      [[ $# ]] || die "--env-file needs a path"
      ENV_FILE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

if [[ ! -f ${ENV_FILE} ]]; then
  die "no ${ENV_FILE}; create it with: cp ${EXAMPLE_ENV_FILE} ${ENV_FILE}"
fi

problems=()
warnings=()

# Required for `docker compose` interpolation in the root docker-compose.yaml.
# RESEND_API_KEY / RESEND_FROM_EMAIL are not just for email delivery:
# backend/internal/configs/config.go declares them `required:"true"` and calls
# os.Exit(1) when validation fails, so an empty value crash-loops the backend.
REQUIRED=(
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_DB
  JWT_SECRET
  RESEND_API_KEY
  RESEND_FROM_EMAIL
  CORS_ORIGINS
  PUBLIC_API_BASE
  PGADMIN_DEFAULT_EMAIL
  PGADMIN_DEFAULT_PASSWORD
)

value_of() { env_get "$1" || true; }

for key in "${REQUIRED[@]}"; do
  [[ -n "$(value_of "${key}")" ]] || problems+=("${key} is missing or empty")
done

# --- format checks (only meaningful once the value is present) ---------------

jwt="$(value_of JWT_SECRET)"
if [[ -n ${jwt} ]]; then
  if [[ ! ${jwt} =~ ^[A-Za-z0-9+/]+={0,2}$ || $(( ${#jwt} % 4 )) -ne 0 ]]; then
    problems+=("JWT_SECRET is not valid base64 (generate one with: openssl rand -base64 32)")
  else
    bytes="$(base64_decoded_bytes "${jwt}" || printf '0')"
    if (( bytes < 32 )); then
      problems+=("JWT_SECRET decodes to ${bytes} bytes; the backend expects at least 32")
    fi
  fi
fi

cors="$(value_of CORS_ORIGINS)"
if [[ -n ${cors} && ${cors} != *"://"* ]]; then
  problems+=("CORS_ORIGINS must be a comma-separated list of origins, e.g. https://opencw.example.com")
fi

api_base="$(value_of PUBLIC_API_BASE)"
if [[ -n ${api_base} && ${api_base} != http*://* ]]; then
  problems+=("PUBLIC_API_BASE must be an absolute URL, e.g. https://api.opencw.example.com/v1")
fi

pgadmin_email="$(value_of PGADMIN_DEFAULT_EMAIL)"
if [[ -n ${pgadmin_email} && ${pgadmin_email} != *"@"* ]]; then
  problems+=("PGADMIN_DEFAULT_EMAIL must be an email address (it is the pgAdmin login, not a PostgreSQL role)")
fi

# --- warnings ---------------------------------------------------------------

if [[ -z "$(value_of CLOUDFLARED_TUNNEL_TOKEN)" ]]; then
  printf -v msg \
    'CLOUDFLARED_TUNNEL_TOKEN is empty: cloudflared has no "profiles:" key, so it starts with\nthe default stack and will restart-loop without a token. Set it in .env, or stop the\nservice with: docker compose stop cloudflared'
  warnings+=("${msg}")
fi

if [[ -z "$(value_of POSTGRES_DATA_PATH)" ]]; then
  warnings+=("POSTGRES_DATA_PATH is unset; Compose falls back to ./data/postgres inside the repo")
fi

pg_password="$(value_of POSTGRES_PASSWORD)"
if [[ -n ${pg_password} && ${#pg_password} -lt 16 ]]; then
  warnings+=("POSTGRES_PASSWORD is shorter than 16 characters")
fi

pgadmin_password="$(value_of PGADMIN_DEFAULT_PASSWORD)"
if [[ -n ${pgadmin_password} && ${#pgadmin_password} -lt 12 ]]; then
  warnings+=("PGADMIN_DEFAULT_PASSWORD is shorter than 12 characters")
fi

if [[ -n ${api_base} && ${api_base} =~ ^https?://(localhost|127\.0\.0\.1) ]]; then
  printf -v msg \
    'PUBLIC_API_BASE is %s, which is baked into the frontend bundle at build time.\nBrowsers will only resolve it on the machine running this stack.' \
    "${api_base}"
  warnings+=("${msg}")
fi

# --- report -----------------------------------------------------------------

if (( ${#problems[@]} )); then
  printf '%s%s has %d problem(s):%s\n' "${C_RED}" "${ENV_FILE}" "${#problems[@]}" "${C_RESET}" >&2
  i=1
  for problem in "${problems[@]}"; do
    printf '  %d. %s\n' "${i}" "${problem}" >&2
    i=$(( i + 1 ))
  done
fi

if (( ${#warnings[@]} )); then
  printf '%s%s has %d warning(s):%s\n' "${C_YELLOW}" "${ENV_FILE}" "${#warnings[@]}" "${C_RESET}" >&2
  nl=$'\n'
  for warning in "${warnings[@]}"; do
    # Each warning is one array entry; continuation lines of a multi-line
    # message keep the list indentation.
    printf '  - %s\n' "${warning//${nl}/${nl}    }" >&2
  done
fi

if (( ${#problems[@]} )); then
  printf '\nSee the "Clone and configure" section of DEPLOYMENT.md.\n' >&2
  exit 1
fi

if (( QUIET == 0 )); then
  ok "${ENV_FILE} is valid (${#warnings[@]} warning(s))"
fi

exit 0
