#!/usr/bin/env bash
# Restore an OpenCW database dump created by scripts/backup.sh.
#
# Destructive by design: the default mode drops and recreates the target
# database so the restore is a clean replacement rather than a merge into
# whatever happens to be there. A pre-restore backup is always taken first
# (unless --no-backup), and the operator has to confirm by typing the database
# name.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DUMP_FILE=''
GLOBALS_FILE=''
MODE='recreate'
WITH_GLOBALS=1
NO_BACKUP=0
KEEP="${BACKUP_RETENTION:-14}"

usage() {
  print_help \
    "Restore an OpenCW database dump. Overwrites the target database." \
    "scripts/restore.sh [FILE] [options]" \
    "FILE                  dump to restore (.sql.gz or .sql); default: newest in ${BACKUP_DIR}" \
    "--file PATH           same as the positional FILE" \
    "--globals PATH        restore roles/grants from a pg_dumpall --globals-only dump" \
    "--no-globals          do not look for a companion .globals.sql.gz next to FILE" \
    "--append              apply the dump on top of the existing schema instead of recreating it" \
    "--no-backup           skip the automatic pre-restore backup (not recommended)" \
    "--keep N              retention for the pre-restore backup (default ${KEEP})"
}

while (( $# )); do
  case "$1" in
    --file)
      shift
      [[ $# ]] || die "--file needs a path"
      DUMP_FILE="$1"
      ;;
    --globals)
      shift
      [[ $# ]] || die "--globals needs a path"
      GLOBALS_FILE="$1"
      ;;
    --no-globals) WITH_GLOBALS=0 ;;
    --append) MODE='append' ;;
    --no-backup) NO_BACKUP=1 ;;
    --keep)
      shift
      [[ $# && $1 =~ ^[0-9]+$ ]] || die "--keep needs a non-negative integer"
      KEEP="$1"
      ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      [[ -z ${DUMP_FILE} ]] || die "unexpected argument: $1 (try --help)"
      DUMP_FILE="$1"
      ;;
  esac
  shift
done

require_docker
require_compose_file
require_env_file

db_name="$(env_get POSTGRES_DB || true)"
[[ -n ${db_name} ]] || die "POSTGRES_DB is not set in ${ENV_FILE}"

# --- resolve the dump -------------------------------------------------------

resolve_file() {
  local candidate="$1"
  if [[ -f ${candidate} ]]; then
    printf '%s\n' "${candidate}"
  elif [[ -f ${ROOT_DIR}/${candidate} ]]; then
    printf '%s\n' "${ROOT_DIR}/${candidate}"
  elif [[ -f ${BACKUP_DIR}/${candidate} ]]; then
    printf '%s\n' "${BACKUP_DIR}/${candidate}"
  else
    return 1
  fi
}

if [[ -z ${DUMP_FILE} ]]; then
  DUMP_FILE="$(latest_backup)"
  [[ -n ${DUMP_FILE} ]] ||
    die "no dumps in ${BACKUP_DIR}; pass a file: scripts/restore.sh /path/to/opencw_<date>.sql.gz"
else
  DUMP_FILE="$(resolve_file "${DUMP_FILE}")" || die "cannot find dump '${DUMP_FILE}'"
fi

# A companion globals dump sits next to the chosen dump (in backups/globals) when
# backup.sh wrote one.
if (( WITH_GLOBALS )) && [[ -z ${GLOBALS_FILE} ]]; then
  sibling="$(companion_globals_for "${DUMP_FILE}")"
  if [[ -f ${sibling} ]]; then
    GLOBALS_FILE="${sibling}"
  fi
fi

case "${DUMP_FILE}" in
  *.gz) decompress=(gzip -dc --) ;;
  *) decompress=(cat --) ;;
esac

if [[ ${DRY_RUN} == 0 ]]; then
  db_state="$(container_state db)"
  case ${db_state} in
    running*) ;;
    *) die "the 'db' service is ${db_state}; start it first with: docker compose up -d db" ;;
  esac
fi

# --- confirm ----------------------------------------------------------------

info "dump:     ${DUMP_FILE} ($(human_size "${DUMP_FILE}"))"
if [[ -n ${GLOBALS_FILE} ]]; then
  info "globals:  ${GLOBALS_FILE}"
else
  info "globals:  none"
fi
info "target:   database '${db_name}' in the 'db' service"

if [[ ${MODE} == 'recreate' ]]; then
  warn "the database '${db_name}' will be DROPPED and recreated, then loaded from the dump"
else
  warn "the dump will be applied ON TOP of the existing '${db_name}' schema"
fi

typed_confirm "${db_name}" "This replaces data in the running OpenCW stack."

# --- pre-restore backup -----------------------------------------------------

if (( NO_BACKUP )); then
  warn "--no-backup: skipping the pre-restore backup"
elif [[ ${DRY_RUN} == 1 ]]; then
  dry_pipe "${SCRIPTS_DIR}/backup.sh --keep ${KEEP}"
else
  info "taking a pre-restore backup first"
  "${SCRIPTS_DIR}/backup.sh" --keep "${KEEP}" ||
    die "the pre-restore backup failed; not touching the database"
fi

# --- restore ----------------------------------------------------------------

if [[ ${DRY_RUN} == 1 ]]; then
  if [[ ${MODE} == 'recreate' ]]; then
    dry_pipe "(cd ${ROOT_DIR} && docker compose -f ${COMPOSE_FILE} exec -T db sh -c 'dropdb -U \"\$POSTGRES_USER\" --if-exists --force \"\$POSTGRES_DB\" && createdb -U \"\$POSTGRES_USER\" -O \"\$POSTGRES_USER\" \"\$POSTGRES_DB\"')"
  fi
  extra=''
  [[ ${MODE} == 'recreate' ]] && extra=' --single-transaction'
  dry_pipe "${decompress[*]} ${DUMP_FILE} | (cd ${ROOT_DIR} && docker compose -f ${COMPOSE_FILE} exec -T db sh -c 'psql -v ON_ERROR_STOP=1${extra} -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\"')"
  [[ -n ${GLOBALS_FILE} ]] &&
    dry_pipe "gzip -dc -- ${GLOBALS_FILE} | (cd ${ROOT_DIR} && docker compose -f ${COMPOSE_FILE} exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d postgres')"
  exit 0
fi

if [[ ${MODE} == 'recreate' ]]; then
  log "dropping and recreating '${db_name}'"
  compose exec -T db sh -c \
    'dropdb -U "$POSTGRES_USER" --if-exists --force "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$POSTGRES_DB"' ||
    die "could not recreate the database"
fi

log "loading ${DUMP_FILE}"
if [[ ${MODE} == 'recreate' ]]; then
  # --single-transaction keeps a failed restore from leaving the database in a
  # half-loaded state.
  if ! "${decompress[@]}" "${DUMP_FILE}" |
    compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 --single-transaction -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null; then
    die "restore failed; the transaction was rolled back. The pre-restore backup is still in ${BACKUP_DIR}."
  fi
else
  if ! "${decompress[@]}" "${DUMP_FILE}" |
    compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null; then
    die "restore failed. The pre-restore backup is still in ${BACKUP_DIR}."
  fi
fi

# --- globals (best effort) --------------------------------------------------

if [[ -n ${GLOBALS_FILE} ]]; then
  log "restoring roles and grants from ${GLOBALS_FILE}"
  if gzip -dc -- "${GLOBALS_FILE}" |
    compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres' >/dev/null; then
    ok "roles and grants restored"
  else
    warn "the globals dump could not be applied (existing roles may conflict); the data restore itself succeeded"
  fi
fi

# --- verify -----------------------------------------------------------------

table_count="$(compose exec -T db sh -c \
  "psql -tA -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -c \"select count(*) from information_schema.tables where table_schema = 'public'\"" |
  tr -d '[:space:]')"

if [[ ${table_count} =~ ^[0-9]+$ ]] && (( table_count > 0 )); then
  ok "restore complete: ${table_count} table(s) in the public schema of '${db_name}'"
else
  warn "restore finished but no tables were found in the public schema; check the dump and 'docker compose logs db'"
fi

info "restart the backend so it reconnects with a fresh connection pool: docker compose restart backend"
