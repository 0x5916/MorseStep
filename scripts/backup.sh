#!/usr/bin/env bash
# Create a portable logical backup of the OpenCW database.
#
# Uses the same pg_dump pipeline that DEPLOYMENT.md section 6 documents, so the
# documented restore command keeps working, and writes gzip-compressed plain-SQL
# dumps into ${BACKUP_DIR}. Old dumps are rotated afterwards.
#
# Credentials are read from inside the `db` container (POSTGRES_USER /
# POSTGRES_DB are part of its environment), so the host never needs to handle
# them.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# backup.sh never prompts, so it has no --yes.
COMMON_OPTS=('--dry-run')

KEEP="${BACKUP_RETENTION:-14}"
WITH_GLOBALS=1
PRINT_PATH=0

usage() {
  print_help \
    "Dump the OpenCW database to ${BACKUP_DIR} and rotate old dumps." \
    "scripts/backup.sh [options]" \
    "--keep N              keep the newest N dumps (default ${KEEP}, or \$BACKUP_RETENTION)" \
    "--dir PATH            write dumps to PATH instead of ${BACKUP_DIR}" \
    "--no-globals          skip the companion pg_dumpall --globals-only dump" \
    "--print-path          print the new dump path on stdout and nothing else"
}

while (( $# )); do
  case "$1" in
    --keep)
      shift
      [[ $# && $1 =~ ^[0-9]+$ ]] || die "--keep needs a non-negative integer"
      KEEP="$1"
      ;;
    --dir)
      shift
      [[ $# ]] || die "--dir needs a path"
      BACKUP_DIR="$1"
      ;;
    --no-globals) WITH_GLOBALS=0 ;;
    --print-path) PRINT_PATH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_docker
require_compose_file

# --print-path promises a clean stdout, so move the log stream aside before any
# other output is produced.
if (( PRINT_PATH )); then
  LOG_STREAM=2
fi

# The dump has to run against a live server, so refuse early with a clear
# message rather than emitting an empty file.
if [[ ${DRY_RUN} == 0 ]]; then
  db_state="$(container_state db)"
  case ${db_state} in
    running*) ;;
    *) die "the 'db' service is ${db_state}; start it first with: docker compose up -d db" ;;
  esac
fi

ensure_backup_dir

stamp="$(now_utc)"
target="${BACKUP_DIR}/opencw_${stamp}.sql.gz"
# Timestamps have one-second resolution, so two runs inside the same second would
# otherwise silently overwrite each other. Keep both.
if [[ -e ${target} ]]; then
  n=2
  while [[ -e "${BACKUP_DIR}/opencw_${stamp}-${n}.sql.gz" ]]; do
    n=$(( n + 1 ))
  done
  target="${BACKUP_DIR}/opencw_${stamp}-${n}.sql.gz"
fi
partial="${target}.partial"

# A failed pg_dump must never leave a file that looks like a usable dump.
# Returns 0 unconditionally: this runs as an EXIT trap while errexit is active, so
# a non-zero result here would turn a successful backup into exit status 1 -- which
# update.sh reads as a failed pre-update backup and aborts the whole update on.
cleanup_partial() {
  [[ -f ${partial} ]] || return 0
  rm -f -- "${partial}"
}
trap cleanup_partial EXIT

if [[ ${DRY_RUN} == 1 ]]; then
  dry_pipe "(cd ${ROOT_DIR} && docker compose -f ${COMPOSE_FILE} exec -T db sh -c 'pg_dump -U \"\$POSTGRES_USER\" \"\$POSTGRES_DB\"') > ${partial}"
  dry_pipe "gzip -c -- ${partial} > ${target} && rm -f -- ${partial}"
  dry_pipe "gzip -t -- ${target}   # abort if the dump is truncated"
  if (( WITH_GLOBALS )); then
    dry_pipe "mkdir -p -- $(globals_dir)"
    dry_pipe "(cd ${ROOT_DIR} && docker compose -f ${COMPOSE_FILE} exec -T db sh -c 'pg_dumpall --globals-only -U \"\$POSTGRES_USER\"') > $(companion_globals_for "${target}")"
  fi
  dry_pipe "prune ${BACKUP_DIR} down to the newest ${KEEP} dump(s)"
else
  info "dumping database to ${target}"
  # Write to ${partial} first: if pg_dump fails mid-stream, pipefail fails the
  # pipeline and the trap removes the incomplete file.
  if ! ( cd -- "${ROOT_DIR}" && docker compose -f "${COMPOSE_FILE}" exec -T db \
        sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' ) > "${partial}"; then
    die "pg_dump failed; ${partial} removed. Check 'docker compose logs db'."
  fi
  gzip -c -- "${partial}" > "${target}"
  rm -f -- "${partial}"

  gzip -t -- "${target}" || die "${target} is not valid gzip"
  size_bytes="$(stat -c %s -- "${target}" 2>/dev/null || printf '0')"
  (( size_bytes > 0 )) || die "${target} is empty"

  if (( WITH_GLOBALS )); then
    globals="$(companion_globals_for "${target}")"
    run mkdir -p -- "$(globals_dir)"
    if ( cd -- "${ROOT_DIR}" && docker compose -f "${COMPOSE_FILE}" exec -T db \
         sh -c 'pg_dumpall --globals-only -U "$POSTGRES_USER"' ) > "${globals}.partial"; then
      gzip -c -- "${globals}.partial" > "${globals}"
      rm -f -- "${globals}.partial"
      gzip -t -- "${globals}" || warn "globals dump ${globals} is not valid gzip"
      log "wrote ${globals}"
    else
      rm -f -- "${globals}.partial"
      warn "pg_dumpall --globals-only failed; continuing without a roles/grants dump"
    fi
  fi

  ok "backup written: ${target} ($(human_size "${target}"))"
  prune_backups "${KEEP}"
fi

if (( PRINT_PATH )); then
  printf '%s\n' "${target}"
fi
