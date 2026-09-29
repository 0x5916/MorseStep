# Operational scripts

A guided tour of the scripts in this directory. They wrap `docker compose` with the validation,
backups, and health checks that a manual `git pull && docker compose up -d --build` leaves out.

The scripts are the source of truth; the root `Makefile` only forwards to them, so `make` is never
the only way to do something.

- Read-only: [`check-env.sh`](#check-envsh), [`status.sh`](#statussh)
- Changes your running stack: [`deploy.sh`](#deploysh), [`update.sh`](#updatesh),
  [`restore.sh`](#restoresh)
- Writes files, leaves the stack alone: [`backup.sh`](#backupsh)

If you only read one section, read [Safety model](#safety-model), then
[Troubleshooting](#troubleshooting).

## Requirements

- Linux with **bash 4 or newer** (macOS ships bash 3.2; the scripts refuse to start with a clear
  message rather than misbehaving).
- Docker Engine with the **Compose v2 plugin** (`docker compose version`).
- `curl` (or `wget`) for the health probes, and `openssl` if you want `deploy.sh` to generate a
  JWT secret for you. `make` is optional.

Run the scripts from anywhere inside the checkout: each one resolves the repository root from its
own path.

## Quick start

```bash
cp example.env .env      # deploy.sh offers to do this for you
nano .env                # fill in the required values
make deploy              # or scripts/deploy.sh

make status              # confirm everything is healthy
make backup              # take a first backup
```

`make` on its own prints every target.

## Everyday tasks

### Check the configuration

```bash
make check
```

Reports **every** problem in `.env` in one pass, then lists warnings for things that work but are
likely to bite later (empty tunnel token, weak passwords, an unset `POSTGRES_DATA_PATH`). Exits `0`
when only warnings are found, `1` when something must be fixed.

### Update the deployment

```bash
make update                    # backup, pull, rebuild, verify
make update DRY_RUN=1          # show what it would do, change nothing
make update REF=v1.2.0         # move to a tag, branch or commit
make update NO_BACKUP=1        # skip the pre-update backup
```

The sequence is: refuse on a dirty working tree, tag the running images
`<image>:pre-<UTC timestamp>`, back up the database, fetch and fast-forward the current branch,
rebuild, then wait for `db`, `backend`, `frontend` and pgAdmin to answer. On failure it prints exact
rollback commands.

### Back up

```bash
make backup                    # newest 14 dumps are kept
make backup KEEP=30            # keep 30
scripts/backup.sh --dir /mnt/backups --keep 0   # write elsewhere, no rotation
```

### Restore

```bash
make restore                                          # newest dump in backups/
make restore FILE=backups/opencw_20260928T101500Z.sql.gz
```

Takes a fresh backup first, then asks you to type the database name before it drops anything. Add
`--append` to load on top of the existing schema instead of replacing it. You will be asked to
restart the backend afterwards so it reconnects with a clean pool.

### Check health

```bash
make status
scripts/status.sh --skip-disk    # faster, when you only care about services
```

### Run as a cron job

`backup.sh` and `status.sh` are designed for unattended use. Always use absolute paths — cron's
`PATH` is minimal.

```cron
# Nightly logical backup at 03:15
15 3 * * * cd /opt/opencw && /opt/opencw/scripts/backup.sh >> /var/log/opencw-backup.log 2>&1

# Every 5 minutes, alert when something is unhealthy (status.sh exits non-zero)
*/5 * * * * cd /opt/opencw && /opt/opencw/scripts/status.sh --skip-disk >/dev/null 2>&1 || /usr/local/bin/notify
```

## Safety model

Every guard exists because of a specific accident it prevents.

| Guard | Accident it prevents |
|-------|----------------------|
| `update.sh` refuses a dirty working tree | Rebuilding from half-committed code, or losing uncommitted edits to a checkout |
| `update.sh` tags images `:pre-<timestamp>` | Having no image to fall back to after a bad release |
| `update.sh` backs up before changing anything | A migration that cannot be reversed (see [Design notes](#design-notes)) |
| `restore.sh` backs up before restoring | Losing the current data by restoring the wrong file |
| `restore.sh` requires the database name to be typed | Wiping a production database with a stray Enter key |
| `restore.sh` runs `psql --single-transaction` | A failed restore leaving a half-loaded database |
| `backup.sh` dumps to a `.partial` file, then verifies with `gzip -t` | A truncated `pg_dump` being archived as a usable backup |
| Globals dumps live in `backups/globals/` | A roles/grants dump being mistaken for a restorable database dump |
| `check-env.sh` validates before building | A 4-minute image build ending in an unrelated startup crash |

## Script reference

All scripts accept `-h`/`--help`. Unless stated otherwise, a failure means exit code `1`; success is
`0`.

### `check-env.sh`

Validates root `.env` against the requirements in [DEPLOYMENT.md](../DEPLOYMENT.md).

| Option | Meaning |
|--------|---------|
| `--quiet` | Print nothing when the file is valid (used by `status.sh`) |
| `--env-file PATH` | Validate `PATH` instead of `.env` |

Read-only. Accepts no `--dry-run` or `--yes`.

### `deploy.sh`

First-time install: bootstraps `.env` from `example.env`, offers to fill an empty `JWT_SECRET`, runs
`check-env.sh`, builds, starts, and waits for every service.

| Option | Meaning |
|--------|---------|
| `--timeout SECONDS` | Per-service wait budget (default `240`) |
| `--dry-run` | Print the commands and the health checks, change nothing |
| `--yes` | Do not prompt for the `.env` copy or the JWT secret |

### `update.sh`

Moves the checkout to a new revision and verifies the result.

| Option | Meaning |
|--------|---------|
| `--ref REF` | Branch, tag or commit to check out (default: fast-forward the current branch) |
| `--no-backup` | Skip the pre-update database backup |
| `--auto-rollback` | Restore the previous images automatically when verification fails |
| `--timeout SECONDS` | Per-service wait budget (default `240`) |
| `--keep N` | Retention for the pre-update backup (default `14`) |
| `--dry-run`, `--yes` | As above |

Requires the current branch to have an upstream, or an explicit `--ref`.

### `backup.sh`

Writes `backups/opencw_<UTC>.sql.gz` and, unless `--no-globals`, a companion
`backups/globals/opencw_<UTC>.globals.sql.gz` holding roles and grants.

| Option | Meaning |
|--------|---------|
| `--keep N` | Keep the newest `N` dumps (default `14`, or `$BACKUP_RETENTION`) |
| `--dir PATH` | Write to `PATH` instead of `backups/` (or `$BACKUP_DIR`) |
| `--no-globals` | Skip the `pg_dumpall --globals-only` companion dump |
| `--print-path` | Print only the new dump's path on stdout — for scripting |
| `--dry-run` | As above |

Never prompts, so it has no `--yes`.

### `restore.sh`

Replaces the database contents with a backup.

| Option | Meaning |
|--------|---------|
| `FILE` / `--file PATH` | Dump to restore; defaults to the newest in `backups/`. Accepts `.sql.gz` or `.sql` |
| `--append` | Apply the dump on top of the existing schema instead of dropping and recreating the database |
| `--globals PATH` | Restore roles/grants from a specific globals dump |
| `--no-globals` | Do not look for a companion globals dump |
| `--no-backup` | Skip the automatic pre-restore backup (not recommended) |
| `--keep N` | Retention for that pre-restore backup (default `14`) |
| `--dry-run`, `--yes` | As above |

Default behaviour is **destructive**: `dropdb --if-exists --force` then `createdb`, so expect a few
seconds of downtime and dropped connections.

### `status.sh`

Prints environment validation, `docker compose ps`, per-service state, HTTP probes, the git
revision, the last recorded release, image list, backup inventory, and disk usage.

| Option | Meaning |
|--------|---------|
| `--skip-disk` | Omit the slower disk and Docker storage sections |

Exits `1` when `.env` is invalid, when `db`, `backend`, `frontend` or `pgadmin` is not running and
healthy, or when the database refuses connections. Read-only, and it deliberately rejects
`--dry-run` — suppressing the `docker` calls would make a healthy stack look like it was never
created.

## Files these scripts create

| Path | Written by | Contents |
|------|-----------|----------|
| `backups/opencw_<UTC>.sql.gz` | `backup.sh` | Migration-safe plain-SQL dump, restorable with the command in DEPLOYMENT.md §6 |
| `backups/globals/opencw_<UTC>.globals.sql.gz` | `backup.sh` | `pg_dumpall --globals-only`: roles and grants |
| `.deploy-state` | `update.sh` | Last release: `UPDATED_AT`, `NEW_REF`, `PREV_REF`, `PREV_BRANCH`, `PREV_BACKUP`, `SNAPSHOTS` |

`backups/` and `.deploy-state` are git-ignored. Image snapshots are tagged
`<image>:pre-<UTC timestamp>` and are never deleted automatically — review them with
`docker images | grep pre-` and remove what you no longer need.

## Environment overrides

| Variable | Used by | Effect |
|----------|---------|--------|
| `BACKUP_RETENTION` | `backup.sh`, `update.sh`, `restore.sh` | Default for `--keep` |
| `BACKUP_DIR` | `backup.sh`, `restore.sh`, `status.sh` | Default for `--dir` |
| `ENV_FILE` | all | Path to the environment file (default `.env`) |
| `PGADMIN_PORT` | `deploy.sh`, `update.sh`, `status.sh` | pgAdmin probe port: environment, then `.env`, then `5050` |
| `API_PORT`, `FRONTEND_PORT` | `deploy.sh`, `update.sh`, `status.sh` | Probe ports, matching the fixed Compose bindings |
| `DRY_RUN=1`, `ASSUME_YES=1` | all | Same as `--dry-run` and `--yes` |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `requires bash 4 or newer` | macOS, or an old distro | Run it on the Linux host, or install bash 5 |
| `unknown argument: --yes` | That script has no prompts | Check `--help`; read-only scripts accept neither `--dry-run` nor `--yes` |
| `the 'db' service is not created` | Stack is not running | `docker compose up -d`, then retry |
| `POSTGRES_DATA_PATH is unset` warning | `example.env` value not copied | Set it in `.env`, or accept the in-repo `./data/postgres` default |
| `pgAdmin: no response` but the UI opens in a browser | `PGADMIN_PORT` changed in `.env` | Already handled — the scripts read it from `.env`. Restart nothing; re-run `make status` |
| `there are uncommitted changes` | Dirty tree, by design | Commit or stash, or use `git -C . stash` first |
| `timed out ... waiting for backend` | Slow first build, or the backend is crash-looping | `docker compose logs backend` |
| `the pre-update backup failed; aborting` | Database down or disc full | Fix the cause; nothing was changed |
| `could not snapshot <image>` | Image not built locally yet | Harmless on a first update; the backup is still your safety net |
| `'main' has no upstream branch` | Branch is not tracking a remote | `git branch --set-upstream-to=origin/main`, or pass `--ref` |

## Design notes

- **`.env` is parsed, never sourced.** It contains values with spaces
  (`RESEND_FROM_EMAIL=OpenCW <no-reply@example.com>`); sourcing the file would try to execute them.
- **Credentials stay out of the host shell.** `pg_dump` runs inside the `db` container and reads
  `$POSTGRES_USER`/`$POSTGRES_DB` from its own environment.
- **Backups are plain-SQL gzip**, not `--format=custom`, so the restore command already documented
  in DEPLOYMENT.md §6 keeps working.
- **Migrations are forward-only.** The backend runs GORM `AutoMigrate` at startup, so rolling the
  images back does **not** undo schema changes. The pre-update backup is the way back. This is why
  `update.sh` backs up before it touches anything, and why `--no-backup` is warned about.
- **stdout is reserved for data.** Informational output goes through a single stream
  (`LOG_STREAM`), which `backup.sh --print-path` points at stderr so a caller capturing stdout gets
  only the path.
