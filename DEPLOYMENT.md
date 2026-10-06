# MorseStep production deployment

Deploy the root [Compose stack](docker-compose.yaml) on a Linux host. Use this procedure for installation and recovery, [scripts/README.md](scripts/README.md) for command flags, [example.env](example.env) for configuration defaults, and [db/README.md](db/README.md) for database tuning. Image versions live in Compose.

## Requirements

Use Docker with Compose v2, Bash 4 or newer, Git, Make, gzip, and curl or wget; OpenSSL generates secrets. The scripts require GNU host utilities, so run them on the deployment host. Enable Docker at boot and reserve space for database data, images, and retained backups.

The shipped bindings expose the database at `${DB_PORT:-5432}`, backend at `8080`, and frontend at `3000` on every interface. pgAdmin binds only to `127.0.0.1:${PGADMIN_PORT:-5050}`. Restrict database and application ports with your firewall or loopback bindings when a tunnel or local proxy supplies public access. Retain the loopback mappings used by health probes.

## Clone and configure

Clone the complete repository; Compose bind-mounts [db/tune.sh](db/tune.sh), so the Compose file alone is insufficient. Run commands from the checkout root.

```bash
cp example.env .env
chmod 600 .env
openssl rand -base64 32
```

Paste the generated value into `JWT_SECRET` and fill the required values below. Keep `.env` out of Git and do not source it as shell code; values such as the sender address contain spaces.

| Configuration | Required values and meaning                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Database      | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`; select `POSTGRES_DATA_PATH` on persistent storage. An unset path falls back to `./data/postgres`. |
| Access tokens | `JWT_SECRET`: base64 bytes; `make check` requires at least 32 decoded bytes.                                                                           |
| Email         | `RESEND_API_KEY`, `RESEND_FROM_EMAIL`; both are required by backend startup validation.                                                                |
| Browser API   | `PUBLIC_API_BASE`: browser-reachable V1 URL, for example `https://api.example.com/v1`. It is embedded when the frontend is built.                      |
| CORS          | `CORS_ORIGINS`: comma-separated frontend origins. This is backend runtime configuration.                                                               |
| pgAdmin       | `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`: separate from database credentials; used to initialize its account.                               |

Set explicit database resource limits on a shared or nested host; see [PostgreSQL resource tuning](#postgresql-resource-tuning). Review optional ports, HTTP timeouts, connection pool settings, and tunnel values in [example.env](example.env), then run `make check`.

## Build and verify

```bash
make deploy
make status
make backup
```

Deployment can bootstrap `.env` and generate a missing JWT secret, but required credentials still need values. It builds the images, waits for database/backend/frontend/pgAdmin container health, and probes backend and frontend HTTP endpoints. A failed pgAdmin HTTP probe warns. `make status` additionally treats an unhealthy or missing pgAdmin container as a failure; its pgAdmin HTTP probe and tunnel problems are warnings.

Local endpoints are frontend `http://127.0.0.1:3000`, health `http://127.0.0.1:8080/v1/health`, and pgAdmin `http://127.0.0.1:5050` unless its port changed. `pgadmin-config` exits after rendering configuration; exit 0 is expected.

## Public access

For Cloudflare Tunnel, configure `CLOUDFLARED_TUNNEL_TOKEN` and route public hostnames to `http://frontend:80`, `http://backend:8080`, and, if needed, `http://pgadmin:80` on the Compose network. Put a restrictive Cloudflare Access policy in front of pgAdmin. `CLOUDFLARED_PROTOCOL` selects the tunnel transport. The service always starts with the stack; an empty token causes restart loops. Stop it explicitly when using a different proxy.

A reverse proxy must terminate TLS and forward the frontend to port 3000 and API to port 8080. Preserve both `/v1` and `/v2` API paths. If adding a public path prefix, include the V1 path in `PUBLIC_API_BASE` and configure proxy rewriting consistently. Rebuild the frontend after changing that value; recreate the backend after changing CORS. Production uses `GIN_MODE=release`, which disables profiling routes; development registers `/debug/pprof/*`, so keep development profiling private.

## Updates and rollback

```bash
make update DRY_RUN=1
make update
```

The update script requires a clean tracked working tree, snapshots locally built images, takes a database backup, fetches and fast-forwards the current branch, rebuilds, and verifies health. Use `scripts/update.sh --ref REVISION` for a branch, tag, or commit. `--auto-rollback` restores prior images on failure; otherwise the script prints rollback commands. The release record is `.deploy-state`. Return from a rollback's detached HEAD to a branch before the next ordinary update.

Backend startup runs GORM `AutoMigrate`. An image rollback does not undo database changes: retain the pre-update dump and restore it when returning to an older schema. `--no-backup` removes that recovery path. See [script flags](scripts/README.md#script-reference).

## pgAdmin administration

pgAdmin's web login uses `PGADMIN_DEFAULT_*`; its database connection uses `POSTGRES_*`. Editing the former after the first initialization does not reset an existing account. Reset through the user interface or the container's `setup.py update-user` command, using the existing login email. Deleting its volume discards saved accounts, servers, and preferences.

The shared [renderer](scripts/render-pgadmin.py) writes `servers.json` and a private per-login `.pgpass` into `pgadmin_data`, escapes all credential fields, and selects that passfile in the connection parameters. It uses host `db`, port 5432, and the configured database role. Startup replaces the configured pgAdmin account's saved server list with this managed OpenCW connection. Bring the stack up after credential changes so the renderer runs; restarting pgAdmin alone does not run it. A password saved separately in pgAdmin must also be updated. The volume holds the database password in plain text; protect it like `.env`. The configured connection uses `sslmode=prefer` and master-password protection is disabled.

## Backups and recovery

```bash
make backup
scripts/backup.sh --dir /mnt/backups
scripts/restore.sh --file backups/opencw_TIMESTAMP.sql.gz
```

Backups are verified gzip plain-SQL dumps, with companion globals dumps for roles and grants. Default retention is 14 dumps; `--keep 0` disables pruning. Restore stages inputs before any database recreation and pins its recovery dump until verification succeeds. Keep copies off the host and protect configuration and pgAdmin state separately. Backup frequency determines how much recent data can be lost; the scripts do not implement continuous recovery.

Restore replaces the live database by default: it requires a database-name confirmation unless `--yes`, takes a pre-restore backup unless `--no-backup`, drops/recreates the database, and loads the data in one transaction. A failed load rolls back that load; the previous database was already dropped. Globals restoration is separate and best-effort. `--append` writes into the existing live schema without the single-transaction guarantee and can leave partial changes. Restart the backend after a successful restore.

Rehearse dumps against a separate scratch database or isolated stack, verify tables and representative records, then remove the scratch database. `--append` against production is not a rehearsal. The restore script accepts its own `.sql` and `.sql.gz` format; pgAdmin custom dumps require `pg_restore` instead.

The root database is a host bind mount at `/var/lib/postgresql`, with `PGDATA=/var/lib/postgresql/18/docker`. A live filesystem copy can be inconsistent; use a stopped or application-consistent snapshot as an additional backup and retain the matching PostgreSQL version. `docker compose down` preserves data; `down -v` removes pgAdmin's named volume but not the database bind mount. Before any deliberate data deletion, resolve the configured path and confirm the cluster under its versioned PGDATA directory.

## Monitoring and credential changes

```bash
scripts/status.sh --skip-disk
docker compose logs --tail=100 backend
docker compose logs db
```

Status reports environment validation, containers, endpoints, database readiness, revision, images, backups, and disk usage. It warns when the newest backup is at least seven days old. Schedule backups and status checks using the [cron example](scripts/README.md#scheduled-runs). Compose caps long-running container logs at three 10 MB files. Services use `restart: unless-stopped`; Docker must start at boot, and deliberately stopped services stay stopped.

Rotate the database role password with psql's `\password` prompt, update `.env`, recreate affected services, and update any saved pgAdmin password. Changing `.env` alone does not alter an initialized PostgreSQL role. Changing `JWT_SECRET` invalidates existing access JWTs after backend recreation; opaque refresh tokens remain valid until revoked or expired. Refresh-token invalidation requires separate database handling. Update Resend credentials and recreate the backend; change an existing pgAdmin password through pgAdmin rather than its initialization variables.

## PostgreSQL resource tuning

The database entrypoint chooses memory from an explicit budget, cgroup limits, then host detection; automatic tuning requires at least 512 MiB. CPU sizing takes the minimum of explicit limits, cgroup quotas, effective cpuset, and available CPUs. On LXC or nested hosts the host fallback can overstate available resources, so set `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` to the database's share. These also enforce Docker limits. Keep `POSTGRES_SHM_SIZE` below the memory ceiling and leave headroom for other services.

[db/README.md](db/README.md) owns the detection order, formulas, clamps, override variables, and troubleshooting. Inspect `docker compose logs db` for the selected budget before accepting a deployment. Recreate the database container to apply configuration changes; do not edit cluster files to tune it.
