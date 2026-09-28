# Production Deployment

OpenCW is deployed as a set of Docker containers orchestrated by Docker Compose:

| Service    | Image                       | Port |
|------------|-----------------------------|------|
| `db`       | `postgres:18.6-alpine3.23`  | —    |
| `backend`  | built from `./backend`      | 8080 |
| `frontend` | built from `./frontend`     | 3000 |
| `pgadmin`  | `dpage/pgadmin4:9.18.0`     | 5050 (loopback only) |
| `pgadmin-config` | `dpage/pgadmin4:9.18.0` | — |

`pgadmin-config` is a one-shot helper that renders pgAdmin's server definition and password file
from `.env` and then exits; an `exited (0)` entry for it in `docker compose ps` is expected.

Tunnel:

| Service       | Image                         | Port |
|---------------|-------------------------------|------|
| `cloudflared` | `cloudflare/cloudflared:latest` | —  |

> `cloudflared` has no `profiles:` key in `docker-compose.yaml`, so it starts with the default
> stack. The `--profile tunnel` flag mentioned in earlier revisions of this document selects nothing.

## Requirements

- Docker ≥ 26 with the Compose plugin (`docker compose version`)
- A reverse proxy (nginx, Caddy, etc.) in front of port 3000 and 8080 for TLS termination

## 1. Clone and configure

```bash
git clone <repo-url>
cd OpenCW
cp example.env .env
```

Edit `.env` and fill in every value:

```dotenv
# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_USER=opencw
POSTGRES_PASSWORD=<strong-random-password>
POSTGRES_DB=opencw

# ── Backend ───────────────────────────────────────────────────────────────────
# Must be base64-encoded bytes (≥ 32 raw bytes).
JWT_SECRET=<output of: openssl rand -base64 32>

# Comma-separated list of origins the browser sends the API requests from.
# Set this to your public frontend URL(s), e.g.:
CORS_ORIGINS=https://opencw.example.com

# ── Frontend (build-time) ─────────────────────────────────────────────────────
# The URL the *browser* uses to reach the backend API.
# Must be publicly reachable — this is baked into the frontend bundle at build time.
PUBLIC_API_BASE=https://api.opencw.example.com/api/v1

# ── pgAdmin 4 (admin UI) ──────────────────────────────────────────────────────
# Login for pgAdmin itself. An email address, NOT a PostgreSQL role, and separate
# from the database credentials above. Set it once — pgAdmin derives its own
# storage paths from it, and the values are only read when pgAdmin's configuration
# database is created.
PGADMIN_DEFAULT_EMAIL=you@example.com
PGADMIN_DEFAULT_PASSWORD=<strong-random-password>
```

Both `PGADMIN_*` values are required: without them the `pgadmin-config` helper exits with an
error and the admin UI does not start.

### Generating a JWT secret

```bash
openssl rand -base64 32
```

The value must be base64-encoded. The backend decodes it at startup and exits if it is missing or malformed.

## 2. Build and start

```bash
docker compose up -d --build
```

`scripts/deploy.sh` performs steps 1 and 2 together: it bootstraps `.env` from `example.env`,
offers to generate `JWT_SECRET`, validates the file against the requirements below, builds the
stack, and waits until every service answers before reporting success.

```bash
make deploy          # or: scripts/deploy.sh
```

Compose will:

1. Pull `postgres:18.6-alpine3.23` and start the database.
2. Wait for the database healthcheck to pass.
3. Build and start the backend (Go, distroless image, `GIN_MODE=release`).
4. Build and start the frontend (SvelteKit Node adapter, `NODE_ENV=production`).
5. Render the pgAdmin connection settings from `.env` and start the admin UI.

Check everything is healthy:

```bash
docker compose ps
docker compose logs --tail=50
```

## 2b. Start with Cloudflare Tunnel (optional)

Set these values in root `.env`:

```dotenv
CLOUDFLARED_TUNNEL_TOKEN=<your-tunnel-token>
CLOUDFLARED_PROTOCOL=quic
```

Then start with the tunnel:

```bash
docker compose up -d --build
```

`cloudflared` starts with the default stack (see the note in the service table above). Add the
`pgadmin.opencw.net` public hostname to the tunnel as described in section 5.

If you need to compare transport latency, switch `CLOUDFLARED_PROTOCOL` to `http2` and re-test p95/p99.

## 3. Reverse proxy

Neither service should be exposed to the public internet directly. Terminate TLS in your reverse proxy and forward:

| Public URL                            | Upstream                 |
|---------------------------------------|--------------------------|
| `https://opencw.example.com`          | `localhost:3000`         |
| `https://api.opencw.example.com`      | `localhost:8080`         |

> If you host both under a single domain (e.g. `/api/v1` path prefix), update
> `PUBLIC_API_BASE` accordingly and rebuild the frontend image.

### Example: Caddy

```
opencw.example.com {
    reverse_proxy localhost:3000
}

api.opencw.example.com {
    reverse_proxy localhost:8080
}
```

### Example: nginx

```nginx
server {
    listen 443 ssl;
    server_name opencw.example.com;
    location / { proxy_pass http://localhost:3000; }
}

server {
    listen 443 ssl;
    server_name api.opencw.example.com;
    location / { proxy_pass http://localhost:8080; }
}
```

## 4. Updates

```bash
git pull
docker compose up -d --build
```

For production use `scripts/update.sh`, which sequences the same steps so that a bad revision
cannot take the stack down unnoticed:

```bash
make update          # or: scripts/update.sh
```

1. Refuses to run when the working tree has uncommitted changes.
2. Tags the running images as `<image>:pre-<UTC timestamp>` so the previous release can be
   restored, and records them in `.deploy-state`.
3. Takes a database backup (skip with `--no-backup`).
4. Fetches, then fast-forwards the current branch. `--ref <branch|tag|commit>` checks out
   something else instead.
5. Rebuilds and recreates only the affected containers.
6. Waits for `db`, `backend`, `frontend` and pgAdmin to answer before reporting success.

When verification fails the script prints the exact rollback commands; `--auto-rollback`
performs the image rollback for you:

```bash
scripts/update.sh --ref v1.2.0 --auto-rollback
```

Preview an update without changing anything:

```bash
make update DRY_RUN=1
```

> **Migrations are forward-only.** The backend runs GORM `AutoMigrate` at startup
> (`backend/internal/databases/db.go`), and those migrations never move backwards. Rolling the
> images back therefore does **not** undo schema changes. The pre-update backup from step 3 is the
> reliable way back — restore it with `scripts/restore.sh --file <dump>`.

Compose will rebuild changed images and recreate only the affected containers. PostgreSQL's data persists in the host directory configured by `POSTGRES_DATA_PATH`; it is not a named Compose volume and is not removed by `docker compose down`.

## 5. Admin UI (pgAdmin 4)

pgAdmin 4 runs in the stack and is reachable at:

| Where | URL | Notes |
|-------|-----|-------|
| Host (loopback) | `http://127.0.0.1:${PGADMIN_PORT:-5050}` | published on `127.0.0.1` only |
| Public | `https://pgadmin.opencw.net` | through the Cloudflare tunnel, behind a Zero Trust Access policy |

### Two logins: which credential is which

pgAdmin has its own login, separate from the database credentials. Mixing them up produces
confusing errors, so keep them straight:

| | pgAdmin login | PostgreSQL credential |
|---|---|---|
| Variables | `PGADMIN_DEFAULT_EMAIL` (an email address, **not** a PostgreSQL role), `PGADMIN_DEFAULT_PASSWORD` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| Logs into | the pgAdmin web UI | the database — used by the backend and by pgAdmin's `db` server |
| Read when | when pgAdmin's configuration database is created for the first time | role and database name at the first start on an empty data directory; password on every connection |
| How to change it later | user menu → *Change Password*, or delete the `pgadmin_data` volume; editing `.env` has no effect on the existing account | password: `ALTER ROLE` + `.env` + `docker compose up -d`; role and database names cannot be changed this way |

Symptoms: if the pgAdmin page itself rejects you it is login #1; if pgAdmin opens but the server
reports `password authentication failed for user "…"` it is login #2.

### How the connection is pre-configured

The one-shot `pgadmin-config` service renders two files into the `pgadmin_data` volume before
pgAdmin starts, using the values in root `.env`:

| File | Contents |
|------|----------|
| `/var/lib/pgadmin/servers.json` | the `db` server: host `db`, port `5432`, username `POSTGRES_USER`, maintenance database `POSTGRES_DB` |
| `/var/lib/pgadmin/storage/<PGADMIN_DEFAULT_EMAIL, @ replaced by _>/.pgpass` | the password, so the server connects without prompting |

Both files are rewritten on every `docker compose up -d`, so `.env` stays the single source of
truth. `docker compose restart pgadmin` does **not** re-run the renderer. If you tick *Save
password* in pgAdmin's server dialog, pgAdmin stores its own copy and stops reading `.pgpass` —
re-enter the password there after rotating `POSTGRES_PASSWORD`.

### Backups through the UI

1. In the tree, right-click the `opencw` database → *Backup…*.
2. Give the file a name (for example `opencw-<date>.dump`), pick the *Custom* format (compressed,
   restorable with `pg_restore`) or *Plain*, then click *Backup*. Progress and logs appear on the
   *Processes* tab.
3. *Tools → Storage Manager* → select the file → *Download*. It lands in your browser's downloads
   folder.

The container ships PostgreSQL client tools 13–18 and defaults to the v18 binaries, matching the
`postgres:18.6` server, so `pg_dump`/`pg_restore` run without version-mismatch errors. Restoring is
the reverse: upload the dump with the Storage Manager, then right-click the database →
*Restore…*.

### Cloudflare Zero Trust

The tunnel container is already part of this stack and reaches pgAdmin over the Compose network as
`pgadmin:80`, so no port has to be opened on the host.

1. Zero Trust → Networks → Tunnels → your tunnel → **Public hostname** → *Add*: subdomain
   `pgadmin`, domain `opencw.net`, service `HTTP` → `pgadmin:80`. Cloudflare creates the DNS record.
2. Zero Trust → Access → Applications → *Add an application* → Self-hosted: `pgadmin.opencw.net`,
   session duration around 8 hours.
3. Add one policy that allows only your own email address (One-time PIN, or your SSO provider). Do
   not add broader rules.

Cloudflare Access is the outer gate and pgAdmin's own login is the inner one — keep both.

## 6. Backups

The same backups can be created and downloaded through the pgAdmin UI — see section 5.

`make backup` (or `scripts/backup.sh`) wraps the command-line equivalent below: it writes a
timestamped dump into `backups/`, verifies it with `gzip -t`, writes a companion
`pg_dumpall --globals-only` dump into `backups/globals/` for roles and grants, and rotates the
older dumps down to the newest 14 (`--keep N`, or `$BACKUP_RETENTION`). Globals dumps live in a
subdirectory so they are never offered as restorable database dumps.

Restore with `make restore` (or `scripts/restore.sh`), which takes a pre-restore backup first and
requires the operator to type the database name before it drops anything.

The command-line equivalent follows.

The root Compose configuration bind-mounts the host directory set by `POSTGRES_DATA_PATH` at `/var/lib/postgresql` in the container. The checked-in `example.env` sets it to `/data/postgres`; Compose falls back to `./data/postgres` if it is unset. PostgreSQL stores its cluster under `/var/lib/postgresql/18/docker`. This is a host path, not a named Docker volume.

Create a portable logical backup with:

```bash
set -o pipefail
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "opencw_$(date +%F).sql.gz"
```

Restore into a running database:

```bash
gunzip -c "opencw_<date>.sql.gz" | docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"'
```

Before an image upgrade, also take a consistent filesystem snapshot of `POSTGRES_DATA_PATH` while PostgreSQL is stopped, or follow the storage provider's documented procedure for an application-consistent snapshot. Do not use a raw copy of the live PostgreSQL data directory as a backup.

## 7. Stopping / removing

Stop without removing data:

```bash
docker compose down
```

`docker compose down -v` does not delete the bind-mounted database data. To erase it, stop the stack and manually remove the directory configured by `POSTGRES_DATA_PATH` (irreversible).

The data path can be set in `.env`:

```dotenv
POSTGRES_DATA_PATH=/data/postgres
```

## Operational scripts

The scripts in `scripts/` are the source of truth; the `Makefile` only forwards to them. All of
them are safe to run repeatedly.

| Script | Make target | Purpose |
|--------|-------------|---------|
| `scripts/check-env.sh` | `make check` | Validate `.env`, reporting every problem at once |
| `scripts/deploy.sh` | `make deploy` | Bootstrap `.env`, build, start, wait for health |
| `scripts/update.sh` | `make update` | Snapshot, back up, move revision, rebuild, verify |
| `scripts/backup.sh` | `make backup` | Dump the database and rotate old dumps |
| `scripts/restore.sh` | `make restore` | Restore a dump (recreates the database by default) |
| `scripts/status.sh` | `make status` | Health, versions, backups and disk usage |

Common flags: `--dry-run` prints the commands instead of running them, `--yes` skips confirmation
prompts, and every script supports `--help`.

Notes:

- `.env` is **parsed, never sourced**. It contains values with spaces
  (`RESEND_FROM_EMAIL=OpenCW <no-reply@example.com>`), and sourcing the file would try to execute
  them.
- `status.sh` exits non-zero when `db`, `backend` or `frontend` is unhealthy, so it can be used
  directly as a cron or monitoring check.
- `check-env.sh` warns when `CLOUDFLARED_TUNNEL_TOKEN` is empty, because `cloudflared` has no
  `profiles:` key: it starts with the default stack and will restart-loop without a token.
- `backup.sh` is safe to schedule. Dumps live in `backups/`, which is git-ignored along with the
  `.deploy-state` release record.

## Environment variable reference

| Variable          | Required | Description |
|-------------------|----------|-------------|
| `POSTGRES_USER`   | yes      | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | yes    | PostgreSQL superuser password |
| `POSTGRES_DB`     | yes      | Database name |
| `POSTGRES_DATA_PATH` | no | Host directory bind-mounted at `/var/lib/postgresql`; `example.env` sets `/data/postgres`, Compose fallback is `./data/postgres`. |
| `PGADMIN_DEFAULT_EMAIL` | yes | Login for the pgAdmin web UI. An email address, not a PostgreSQL role. Set once: pgAdmin derives its storage paths from it. |
| `PGADMIN_DEFAULT_PASSWORD` | yes | Password for the pgAdmin web UI login, read when pgAdmin's configuration database is first created. |
| `PGADMIN_PORT` | no | Host port for the pgAdmin UI, published on `127.0.0.1` only, default `5050`. |
| `JWT_SECRET`      | yes      | Base64-encoded secret (≥ 32 raw bytes). Backend exits on startup if missing. |
| `CORS_ORIGINS`    | yes      | Comma-separated allowed browser origins, e.g. `https://opencw.example.com` |
| `PUBLIC_API_BASE` | yes      | Browser-visible backend URL, baked into the frontend at build time, e.g. `https://api.opencw.example.com/api/v1` |
| `READ_TIMEOUT` | no | Backend request read timeout (Go duration), default `15s` |
| `READ_HEADER_TIMEOUT` | no | Backend header read timeout, default `5s` |
| `WRITE_TIMEOUT` | no | Backend response write timeout, default `30s` |
| `IDLE_TIMEOUT` | no | Backend keep-alive idle timeout, default `120s` |
| `SHUTDOWN_TIMEOUT` | no | Graceful shutdown timeout, default `20s` |
| `DB_MAX_OPEN_CONNS` | no | Backend DB max open connections, default `25` |
| `DB_MAX_IDLE_CONNS` | no | Backend DB max idle connections, default `5` |
| `DB_CONN_MAX_LIFETIME` | no | Backend DB connection max lifetime, default `30m` |
| `DB_CONN_MAX_IDLE_TIME` | no | Backend DB connection max idle time, default `5m` |
| `CLOUDFLARED_TUNNEL_TOKEN` | no | Cloudflare Tunnel token used when running `--profile tunnel` |
| `CLOUDFLARED_PROTOCOL` | no | Connector transport protocol (`quic` or `http2`), default `quic` |
