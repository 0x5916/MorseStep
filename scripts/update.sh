#!/usr/bin/env bash
# Update a deployed OpenCW stack safely.
#
# Sequence: snapshot the running images and the current commit, take a database
# backup, move to the target revision, rebuild, and verify that every service
# answers. If verification fails the operator gets exact rollback commands, and
# with --auto-rollback the previous images are restored automatically.
#
# Note: the backend runs GORM AutoMigrate at startup (backend/internal/databases/db.go)
# and those migrations are forward-only, so rolling the images back does not undo
# schema changes. The pre-update backup is the reliable way back.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REF=''
NO_BACKUP=0
AUTO_ROLLBACK=0
TIMEOUT=240
KEEP="${BACKUP_RETENTION:-14}"

SNAPSHOTS=()
PREV_REF=''
PREV_BRANCH=''
PREV_BACKUP=''

usage() {
  print_help \
    "Pull the latest code, rebuild, and verify the stack came back healthy." \
    "scripts/update.sh [options]" \
    "--ref REF             update to REF (branch, tag or commit) instead of pulling the current branch" \
    "--no-backup           skip the pre-update database backup" \
    "--auto-rollback       restore the previous images automatically if verification fails" \
    "--timeout SECONDS     how long to wait for each service (default ${TIMEOUT})" \
    "--keep N              retention for the pre-update backup (default ${KEEP})"
}

while (( $# )); do
  case "$1" in
    --ref)
      shift
      [[ $# ]] || die "--ref needs a revision"
      REF="$1"
      ;;
    --no-backup) NO_BACKUP=1 ;;
    --auto-rollback) AUTO_ROLLBACK=1 ;;
    --timeout)
      shift
      [[ $# && $1 =~ ^[0-9]+$ ]] || die "--timeout needs a number of seconds"
      TIMEOUT="$1"
      ;;
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
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_docker
require_compose_file
require_git_checkout
require_env_file

git_step() {
  local description="$1"
  shift
  if [[ ${DRY_RUN} == 1 ]]; then
    printf '%s[dry-run]%s git -C %s %s\n' "${C_DIM}" "${C_RESET}" "${ROOT_DIR}" "$(_quote_cmd "$@")"
    return 0
  fi
  log "${description}"
  ( cd -- "${ROOT_DIR}" && git "$@" )
}

# --- rollback helpers -------------------------------------------------------

snapshot_rollback_lines() {
  local pair
  for pair in "${SNAPSHOTS[@]}"; do
    printf '  docker tag %s %s\n' "${pair##*|}" "${pair%%|*}"
  done
}

print_rollback_help() {
  printf '\n' >&2
  warn "the update did not come up cleanly"
  {
    printf 'Roll back with:\n\n'
    printf '  git -C %s checkout --detach %s\n' "${ROOT_DIR}" "${PREV_REF}"
    if (( ${#SNAPSHOTS[@]} )); then
      snapshot_rollback_lines
    else
      printf '  # no image snapshots were taken (no local images before the rebuild)\n'
    fi
    printf '  docker compose -f %s up -d --no-build\n\n' "${COMPOSE_FILE}"
    if [[ -n ${PREV_BACKUP} ]]; then
      printf 'If the application is broken rather than the images, restore the pre-update dump:\n\n'
      printf '  scripts/restore.sh --file %s\n\n' "${PREV_BACKUP}"
    fi
    printf 'AutoMigrate runs at backend startup and is forward-only, so an image rollback does\n'
    printf 'not undo schema changes. Re-run with --auto-rollback to do the image part for you.\n\n'
    printf 'The rollback leaves the checkout on a detached HEAD, so before your next update\n'
    printf 'return to a branch (and fix whatever the failure was, e.g. .env):\n\n'
    printf '  git -C %s checkout %s\n' "${ROOT_DIR}" "$(resume_branch)"
  } >&2
}

# Branch to tell the operator to return to: the one recorded by the last
# successful update, falling back to main. Reads "HEAD" when the checkout is
# already detached.
resume_branch() {
  local branch
  branch="$(state_get PREV_BRANCH || true)"
  if [[ -z ${branch} || ${branch} == HEAD ]]; then
    printf 'main'
  else
    printf '%s' "${branch}"
  fi
}

fail_update() {
  print_rollback_help

  if (( AUTO_ROLLBACK )) && [[ ${DRY_RUN} == 0 ]]; then
    printf '\n' >&2
    warn "--auto-rollback: restoring the previous release"
    if ! ( cd -- "${ROOT_DIR}" && git checkout --detach "${PREV_REF}" ); then
      die "could not check out ${PREV_REF}; roll back manually using the commands above"
    fi
    local pair
    for pair in "${SNAPSHOTS[@]}"; do
      docker tag "${pair##*|}" "${pair%%|*}" ||
        warn "could not restore image ${pair%%|*} from ${pair##*|}"
    done
    if compose up -d --no-build; then
      ok "the previous images are running again; the database may still carry newer migrations"
      info "review 'docker compose logs --tail=100 backend' and consider scripts/restore.sh"
    else
      warn "the automatic rollback did not complete; use the commands above"
    fi
  fi

  exit 1
}

# --- 1. record the current state -------------------------------------------

if [[ ${DRY_RUN} == 0 ]]; then
  if [[ -n "$( cd -- "${ROOT_DIR}" && git status --porcelain --untracked-files=no )" ]]; then
    die "there are uncommitted changes in ${ROOT_DIR}; commit or stash them first (git -C ${ROOT_DIR} status)"
  fi
fi

PREV_REF="$( cd -- "${ROOT_DIR}" && git rev-parse HEAD )"
PREV_BRANCH="$( cd -- "${ROOT_DIR}" && git rev-parse --abbrev-ref HEAD )"
stamp="$(now_utc)"

info "current revision: ${PREV_REF:0:12} (${PREV_BRANCH})"

# Snapshot the images that are about to be replaced so a rollback has something
# to restore. Compose derives the names; only existing local images can be tagged.
if [[ ${DRY_RUN} == 1 ]]; then
  # Deliberately does not call list_stack_images here: under --dry-run that
  # helper only echoes its own command instead of resolving real image names.
  printf '%s[dry-run]%s for each name from "docker compose config --images": docker tag <image> <image>:pre-%s\n' \
    "${C_DIM}" "${C_RESET}" "${stamp}" >&"${LOG_STREAM}"
else
  while IFS= read -r image; do
    [[ -n ${image} ]] || continue
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      log "no local image for ${image}; skipping snapshot"
      continue
    fi
    snap="$(tag_snapshot_ref "${image}" "pre-${stamp}")"
    # A failed snapshot is worth a warning, not an abort: the backup in step 2 is
    # the primary safety net and the update itself may still be fine.
    if docker tag "${image}" "${snap}" 2>/dev/null; then
      SNAPSHOTS+=("${image}|${snap}")
      log "snapshot: ${image} -> ${snap}"
    else
      warn "could not snapshot ${image} as ${snap}; rollback will not include it"
    fi
  done < <(built_stack_images)
fi

# --- 2. back up before touching anything ------------------------------------

if (( NO_BACKUP )); then
  warn "--no-backup: skipping the pre-update database backup"
elif [[ ${DRY_RUN} == 1 ]]; then
  dry_pipe "${SCRIPTS_DIR}/backup.sh --keep ${KEEP}"
else
  info "taking a pre-update database backup"
  PREV_BACKUP="$("${SCRIPTS_DIR}/backup.sh" --keep "${KEEP}" --print-path)" ||
    die "the pre-update backup failed; aborting before any change"
  ok "pre-update backup: ${PREV_BACKUP}"
fi

# --- 3. move to the target revision ----------------------------------------

if [[ -n ${REF} ]]; then
  git_step "fetching" fetch --all --tags --prune
  git_step "checking out ${REF}" checkout "${REF}"
else
  # A detached HEAD has no upstream, so `git pull` cannot work. That is the state
  # a rollback leaves behind, so name the branch to return to rather than
  # reporting a bare missing-upstream error.
  if [[ ${PREV_BRANCH} == HEAD ]]; then
    die "the checkout is in a detached HEAD state (a rollback leaves it that way), which has no upstream to pull. Return to a branch first: git -C ${ROOT_DIR} checkout $(resume_branch)"
  fi
  upstream="$( cd -- "${ROOT_DIR}" && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true )"
  if [[ -z ${upstream} ]]; then
    die "'${PREV_BRANCH}' has no upstream branch; pass a revision explicitly with --ref"
  fi
  git_step "pulling ${upstream} (fast-forward only)" pull --ff-only
fi

if [[ ${DRY_RUN} == 1 ]]; then
  new_ref="${PREV_REF}"
else
  new_ref="$( cd -- "${ROOT_DIR}" && git rev-parse HEAD )"
fi

if [[ ${new_ref} == "${PREV_REF}" ]]; then
  log "already at ${new_ref:0:12}; rebuilding in case dependencies or build args changed"
else
  ok "moving ${PREV_REF:0:12} -> ${new_ref:0:12}"
fi

# --- 4. rebuild -------------------------------------------------------------

info "rebuilding and restarting changed services"
if ! compose up -d --build; then
  fail_update
fi

# --- 5. verify --------------------------------------------------------------

if [[ ${DRY_RUN} == 1 ]]; then
  dry_pipe "wait for db/backend/frontend/pgadmin, then probe /v1/health"
else
  info "verifying the stack (timeout ${TIMEOUT}s per service)"
  verified=1
  wait_service_healthy db "${TIMEOUT}" || verified=0
  wait_service_healthy backend "${TIMEOUT}" || verified=0
  wait_service_healthy frontend "${TIMEOUT}" || verified=0
  # Only probe over HTTP once the containers themselves are up. Probing an
  # endpoint whose container has already failed just burns the full timeout.
  if (( verified )); then
    wait_http "backend API" "http://127.0.0.1:${API_PORT}/v1/health" "${TIMEOUT}" || verified=0
    wait_http "frontend" "http://127.0.0.1:${FRONTEND_PORT}/" "${TIMEOUT}" || verified=0
    wait_http "pgAdmin" "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" "${TIMEOUT}" || true
  else
    warn "skipping the HTTP probes because a container did not become healthy"
  fi

  if (( verified == 0 )); then
    fail_update
  fi
fi

# --- 6. record the release --------------------------------------------------

if (( ${#SNAPSHOTS[@]} )); then
  joined=''
  for pair in "${SNAPSHOTS[@]}"; do
    joined+="${joined:+ }${pair##*|}"
  done
  state_set SNAPSHOTS "${joined}"
else
  state_set SNAPSHOTS ''
fi
state_set PREV_REF "${PREV_REF}"
state_set PREV_BRANCH "${PREV_BRANCH}"
state_set PREV_BACKUP "${PREV_BACKUP}"
state_set NEW_REF "${new_ref}"
state_set UPDATED_AT "$(date -u +%FT%TZ)"

printf '\n'
ok "update complete: ${PREV_REF:0:12} -> ${new_ref:0:12}"
printf '\n'
printf '  Revision    %s\n' "${new_ref}"
printf '  Backup      %s\n' "${PREV_BACKUP:-none (--no-backup)}"
printf '  Rollback    git -C %s checkout --detach %s\n' "${ROOT_DIR}" "${PREV_REF}"
if (( ${#SNAPSHOTS[@]} )); then
  printf '\nImage snapshots kept for rollback (review them with "docker images | grep pre-"):\n'
  snapshot_rollback_lines
fi
printf '\n'
printf 'Check the result with: make status\n'
