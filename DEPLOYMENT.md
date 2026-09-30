# Production Deployment

OpenCW is deployed as a set of Docker containers orchestrated by Docker Compose:

| Service    | Image                       | Published on |
|------------|-----------------------------|--------------|
| `db`       | `postgres:18.6-alpine3.23`  | `${DB_PORT:-5432}` — every interface |
| `backend`  | built from `./backend`      | `8080` — every interface |
| `frontend` | built from `./frontend`     | `3000` — every interface |
| `pgadmin`  | `dpage/pgadmin4:9.18.0`     | `127.0.0.1:${PGADMIN_PORT:-5050}` — loopback only |
| `pgadmin-config` | `dpage/pgadmin4:9.18.0` | not published (one-shot helper) |
| `cloudflared` | `cloudflare/cloudflared:2026.9.3` | not published (outbound only) |

`db`, `backend` and `frontend` are published on every interface as shipped — setting `DB_PORT` moves
the port, it does not narrow the binding. [The suggested path](#the-suggested-path) narrows them to
loopback. Only pgAdmin is bound that way already.

`pgadmin-config` is a one-shot helper that renders pgAdmin's server definition and password file
from `.env` and then exits; an `exited (0)` entry for it in `docker compose ps` is expected.

`cloudflared` has no `profiles:` key in `docker-compose.yaml`, so it always starts with the stack —
there is no tunnel profile to enable. Without `CLOUDFLARED_TUNNEL_TOKEN` it restart-loops, which
`make check` warns about and `make status` reports as unhealthy.

## Which document owns what

- **This file** — the procedure: install, configure, deploy, verify, upgrade, recover.
- **[scripts/README.md](scripts/README.md)** — the tool reference: every script flag and option, the
  safety model, exit codes, cron examples and operational troubleshooting.
- **[example.env](example.env)** — the variable list, with the reasoning for each value.
- **[db/README.md](db/README.md)** — PostgreSQL tuning: how the database sizes itself and how to
  override it.

## The suggested path

Public traffic reaches this stack through the **Cloudflare Tunnel**, and nothing is published to the
network. The tunnel is outbound-only: it needs no inbound port, no certificate on the host and no DNS
record for you to maintain, and it reaches `frontend`, `backend` and `pgadmin` over the Compose
network by service name.

| Route | When to use it | What it costs you |
|-------|----------------|-------------------|
| **Cloudflare Tunnel** (recommended) | You have a Cloudflare account for the domain | Nothing inbound is opened; pgAdmin's access control comes from Zero Trust (section 5) |
| Reverse proxy with TLS | Cloudflare is not an option | You own the certificates, their renewal, and the `/debug/` denial — see section 3 |
| Both | Only if something must be served from the host itself | Two things to keep correct instead of one |

Because the tunnel connects to containers over the Compose network, `db`, `backend` and `frontend` do
not need to be reachable from the network at all. Narrow their published ports to loopback:

| Service | In `docker-compose.yaml` | Why the mapping stays |
|---------|--------------------------|-----------------------|
| `frontend` | `127.0.0.1:3000:80` | `deploy.sh`, `update.sh` and `status.sh` probe `127.0.0.1:3000` |
| `backend` | `127.0.0.1:8080:8080` | the same scripts probe `127.0.0.1:8080/v1/health` |
| `db` | `127.0.0.1:${DB_PORT:-5432}:5432` | keeps the database off the network; only containers talk to it |

**Do not delete those mappings.** The probes are how `make deploy` and `make status` decide the stack
is working, so removing them turns a healthy deployment into a failing check. Loopback keeps them
working and closes the exposure. `pgadmin` is already bound that way.

### Where things go

| What | Path | Notes |
|------|------|-------|
| Checkout | `/opt/opencw` | owned by root, mode 755 |
| `.env` | `/opt/opencw/.env` | mode 600, git-ignored; the scripts find it from their own location |
| Database | `/data/postgres`, via `POSTGRES_DATA_PATH` | one host directory, bind-mounted at `/var/lib/postgresql`; on a small LXC this is the root disk, so give it a real mount in production |
| Backups | `/opt/opencw/backups` | override with `BACKUP_DIR` or `--dir` to keep them off the host (section 6) |
| Release record | `/opt/opencw/.deploy-state` | written by `update.sh`, git-ignored |
| pgAdmin state | Docker volume `pgadmin_data` | holds the rendered `.pgpass`, in plain text |

### The install path

The rest of this document expands on each step below. This is the order they run in, and the check
that says each one worked.

1. **Prepare the host.** Install Docker Engine 26+ with the Compose v2 plugin, `git`, `make`, `curl`
   and `openssl`, then enable the daemon at boot. On Debian:
   `apt-get install -y --no-install-recommends docker.io docker-cli docker-compose git curl make ca-certificates openssl`,
   then `systemctl enable --now docker` (or `service docker start` where there is no systemd).
   *Gate:* `docker compose version` answers and `bash --version` is 4 or newer.
2. **Create the layout.** Create the checkout's parent if this is a minimal image
   (`install -d -m 755 /opt`). If the database gets its own storage, mount it now and confirm with
   `findmnt /data` — the data directory itself is created on first start by the bind mount.
   *Gate:* `/opt` is writable, and `findmnt /data` shows the mount if you added one.
3. **Get the code.** `git clone <repo-url> /opt/opencw`, or copy the tree when there is no remote. The
   whole checkout is needed, not just the compose file: `db/tune.sh` is bind-mounted from it.
   *Gate:* `git -C /opt/opencw status` runs and `db/tune.sh` exists.
4. **Narrow the published ports.** Apply the three loopback bindings above.
   *Gate:* `docker compose config -q` passes. Skip this only if a host firewall already blocks them.
5. **Configure `.env`.** `make deploy` bootstraps it from `example.env` and offers to generate
   `JWT_SECRET`; or copy it and fill it in by hand. The required values are in section 1. On an LXC,
   also set `POSTGRES_MEMORY_LIMIT=3g` and `POSTGRES_CPU_LIMIT=4`: without a declared budget the tuner
   has to guess, and it refuses to guess above 4 GiB — see [db/README.md](db/README.md). Then
   `chmod 600 .env`.
   *Gate:* `make check` exits 0.
6. **Deploy.** `make deploy`.
   *Gate:* it reports success, which means `.env` validated, the images built, and `db`, `backend`,
   `frontend` and `pgadmin` all answered.
7. **Verify.** `make status`, then `make backup`.
   *Gate:* `make status` is green and a dump exists. Also read the database's own report,
   `docker compose logs db | grep opencw-pg-tune`, and confirm the budget came from
   `POSTGRES_MEMORY_LIMIT` rather than the fallback warning.
8. **Expose it.** Set `CLOUDFLARED_TUNNEL_TOKEN`, `docker compose up -d cloudflared`, then create the
   public hostnames and the Zero Trust policy (sections 2 and 5).
   *Gate:* every hostname answers, and pgAdmin asks Zero Trust for a decision before it asks you for a
   password.
9. **Automate and prove recovery.** Schedule the backup and the health check (section 7), point the
   backups at storage that is not this host, and rehearse a restore into a scratch database
   (section 6).
   *Gate:* a scheduled run produces a dump where you expect it, and the rehearsal loads it.

### What working looks like

`make status` green; the public hostnames answering; the newest dump on storage that is not this
host; `/debug/pprof/` returning 404 from outside; and none of ports 3000, 8080 or 5432 answering
from another machine.

### Upgrading an existing install

Add the `POSTGRES_*` values to `.env` first, run `make check`, then `make update`. The `db` container
is recreated once, which is when the tuner takes effect — a few seconds of database downtime.

## Requirements

**Host**

- Linux with Docker Engine 26 or newer and the Compose v2 plugin (`docker compose version`). Debian
  splits the daemon (`docker.io`) from the CLI (`docker-cli`) and ships Compose as
  `docker-compose`, which already registers itself as a Compose plugin.
- `git` to clone and update, `make` to drive the scripts, `openssl` to generate secrets, and
  `curl` or `wget` for the health probes.
- The scripts in `scripts/` need bash 4 or newer. macOS ships 3.2 and they refuse to start there, so
  run them on the deployment host.
- Disk: room for the images and build cache, for the database under `POSTGRES_DATA_PATH`, and for
  the retained dumps (14 by default). `make status` reports all three.

**Resources**

- No fixed RAM or CPU figure to size against: the `db` service derives its settings from what the
  container actually has — see [PostgreSQL resource tuning](#postgresql-resource-tuning). On a host
  that runs anything else, set `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` in `.env` so
  PostgreSQL sizes itself against its own share rather than the whole machine. On an LXC or
  nested-container host this is **required** rather than advisory: `/proc/meminfo` there reports the
  physical machine.
- Everything else is small — the backend is a static Go binary, the frontend is static files behind
  nginx, and pgAdmin is the largest of the rest. Budget about 2 GB of RAM on top of the database's.

**Network**

- Public access through the Cloudflare Tunnel (recommended — see [The suggested path](#the-suggested-path)),
  or a reverse proxy in front of ports 3000 and 8080 if Cloudflare is not an option.
- Nothing restricts the three application ports as shipped: they publish on every interface. Narrow
them to loopback as the suggested path describes, or block them in the host firewall.

## 1. Clone and configure

The stage-by-stage version of this section, with the check between each step, is
[The suggested path](#the-suggested-path).

```bash
git clone <repo-url> /opt/opencw
cd /opt/opencw
cp example.env .env
```

Edit `.env` and fill in every value:

```dotenv
# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_USER=opencw
POSTGRES_PASSWORD=<strong-random-password>
POSTGRES_DB=opencw
# Host port for the database. It is published on every interface, so the host firewall is what
# keeps it private (section 3); changing the port only moves it.
DB_PORT=5432

# Optional. Give PostgreSQL an explicit share of the host. Without these it sizes itself
# from the container's cgroup limit, or from half of the host's memory when there is none.
# See "PostgreSQL resource tuning" below.
# POSTGRES_MEMORY_LIMIT=2g
# POSTGRES_CPU_LIMIT=2

# ── Backend ───────────────────────────────────────────────────────────────────
# Must be base64-encoded bytes (≥ 32 raw bytes).
JWT_SECRET=<output of: openssl rand -base64 32>

# Resend credentials. The backend validates both on startup and exits if either is
# empty, so a blank RESEND_API_KEY crash-loops the container rather than merely
# disabling email delivery.
RESEND_API_KEY=<your Resend API key>
RESEND_FROM_EMAIL=OpenCW <no-reply@your-domain.example>

# Comma-separated list of origins the browser sends the API requests from.
# Set this to your public frontend URL(s), e.g.:
CORS_ORIGINS=https://opencw.example.com

# ── Frontend (build-time) ─────────────────────────────────────────────────────
# The URL the *browser* uses to reach the backend API, including the API's own path prefix.
# The backend serves everything under /v1, so the value ends in /v1 — not /api/v1.
# Must be publicly reachable — this is baked into the frontend bundle at build time.
PUBLIC_API_BASE=https://api.opencw.example.com/v1

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

1. Pull `postgres:18.6-alpine3.23` and start the database. Its `db/tune.sh` entrypoint sizes
   PostgreSQL from the resources the container actually has and logs what it chose.
2. Wait for the database healthcheck to pass.
3. Build and start the backend (Go, distroless image, `GIN_MODE=release`).
4. Build and start the frontend: SvelteKit `adapter-static`, pre-rendered at build time into an
   nginx image. There is no Node process at runtime.
5. Render the pgAdmin connection settings from `.env`, then start the admin UI.
6. Start `cloudflared` if a tunnel token is set.

### Verify the deployment

`make deploy` waits for the services itself. To re-check a running stack — or to verify one you
started by hand — use the same tools it does:

```bash
make status          # health probes, versions, backups and disk usage
make check           # .env is valid
make backup          # proves the database is reachable and dumpable
```

`make status` probes the endpoints the stack exposes: `/v1/health` on the backend, `/` on the
frontend and `/misc/ping` in pgAdmin, plus `pg_isready` inside `db`. It exits non-zero when any of
them fails, so a green `make status` is this deployment's definition of working.

Expected noise: an `exited (0)` entry for `pgadmin-config`, which is a one-shot helper. A service
that is crash-looping is reported by `make status` as unhealthy rather than as merely up. `db`,
`pgadmin` and `frontend` have Compose healthchecks; `backend` cannot, because its distroless image
contains no shell or HTTP client to run one with — a backend that is running but wedged is only
caught by the `/v1/health` probe above.

### Starting with a Cloudflare Tunnel

Set these in root `.env` before starting, or edit them and restart `cloudflared`:

```dotenv
CLOUDFLARED_TUNNEL_TOKEN=<your-tunnel-token>
CLOUDFLARED_PROTOCOL=quic
```

There is nothing else to enable: `cloudflared` has no `profiles:` key, so it starts with the stack
regardless. An empty token makes it restart-loop; `make check` warns about it and `make status`
reports it as unhealthy.

In the Cloudflare dashboard, give the tunnel a public hostname for each service it should reach:

| Public hostname          | Service                | Notes |
|--------------------------|------------------------|-------|
| `opencw.example.com`     | `HTTP` → `frontend:80` | the app |
| `api.opencw.example.com` | `HTTP` → `backend:8080` | the API the browser calls |
| `pgadmin.opencw.net`     | `HTTP` → `pgadmin:80`  | restrict with Zero Trust — see section 5 |

The hostnames have to match `CORS_ORIGINS` (the frontend origin) and `PUBLIC_API_BASE` (the API
origin), because both are baked into the frontend bundle at build time.

Nothing has to be opened on the host for any of this: the tunnel reaches the services over the
Compose network, which is why [The suggested path](#the-suggested-path) narrows the published ports
to loopback.

If you need to compare transport latency, switch `CLOUDFLARED_PROTOCOL` to `http2` and re-test
p95/p99.

## 3. Reverse proxy and TLS

This is the alternative to [The suggested path](#the-suggested-path), for hosts without Cloudflare.
Terminating TLS here means you own the certificates, their renewal, and the `/debug/` denial that a
tunnel never needs.

Either way, `db`, `backend` and `frontend` should not be reachable from the network: use the loopback
bindings the suggested path describes, or block those ports in the host firewall instead. With that
in place, forward:

| Public URL                       | Upstream         |
|----------------------------------|------------------|
| `https://opencw.example.com`     | `localhost:3000` |
| `https://api.opencw.example.com` | `localhost:8080` |

If the proxy runs on another host, the ports have to stay reachable from it: restrict them to its
address in the firewall rather than binding them to loopback.

Two things the proxy must do beyond terminating TLS:

- **Deny `/debug/`.** The backend registers Go's `net/http/pprof` handlers under `/debug/pprof/*`
  without authentication (`backend/cmd/api-server/main.go` calls `server.PprofSetup`, defined in
  `backend/internal/server/router.go`). A plain `location /` rule would publish heap, goroutine and
  CPU profiles, and `/debug/pprof/profile` can be used to burn CPU on demand. The examples below
  return 404 for that prefix.
- **Forward only what is needed.** The API lives under `/v1`, so scoping the API host to that prefix
  is tighter than forwarding everything. Today nothing else is served, but the margin is free.

> If you serve both under one domain behind a path prefix, `PUBLIC_API_BASE` must include that
> prefix (for example `https://opencw.example.com/api/v1`) because it is baked into the frontend
> bundle at build time — changing it means rebuilding the frontend image.

### Example: nginx

```nginx
# Frontend
server {
    listen 443 ssl;
    http2 on;
    server_name opencw.example.com;

    ssl_certificate     /etc/letsencrypt/live/opencw.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/opencw.example.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# API
server {
    listen 443 ssl;
    http2 on;
    server_name api.opencw.example.com;

    ssl_certificate     /etc/letsencrypt/live/api.opencw.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.opencw.example.com/privkey.pem;

    # Never expose Go's profiling endpoints — see the note above.
    location /debug/ { deny all; return 404; }

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

The certificate paths are examples; point them at wherever your certificates live, and reload the
proxy after a renewal.

### Example: Caddy

```
opencw.example.com {
    reverse_proxy localhost:3000
}

api.opencw.example.com {
    @pprof path /debug/*
    respond @pprof 404
    reverse_proxy localhost:8080
}
```

Caddy obtains and renews certificates itself, which is why it is the shorter option.

## 4. Updates and rollback

Use the wrapper:

```bash
make update          # or: scripts/update.sh
```

> `git pull && docker compose up -d --build` performs the same rebuild, but skips everything that
> makes an update recoverable: the pre-update database backup, the image snapshots, the dirty-tree
> check and the verification. Because the migrations are forward-only (below), the backup is the
> only way back — use the script for anything you care about.

`scripts/update.sh` sequences the steps so that a bad revision cannot take the stack down
unnoticed:

```bash
make update          # or: scripts/update.sh
```

1. Refuses to run when the working tree has uncommitted changes.
2. Tags the images it builds (`opencw-backend`, `opencw-frontend`) as
   `<image>:pre-<UTC timestamp>` so the previous release can be restored, and records them in
   `.deploy-state`. Images that are merely pulled from a registry are not retagged.
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

The `Makefile` forwards `DRY_RUN`, `YES`, `TIMEOUT`, `REF`, `NO_BACKUP` and `KEEP`, but not
`--auto-rollback`, so that one has to be called on the script directly.

Preview an update without changing anything:

```bash
make update DRY_RUN=1
```

> **Migrations are forward-only.** The backend runs GORM `AutoMigrate` at startup
> (`backend/internal/databases/db.go`), and those migrations never move backwards. Rolling the
> images back therefore does **not** undo schema changes. The pre-update backup from step 3 is the
> reliable way back — restore it with `scripts/restore.sh --file <dump>`.

So there are two different ways back, and which one you want depends on what broke:

| Situation | What to do |
|-----------|------------|
| The new revision misbehaves and the schema is unchanged | Roll the images back: `--auto-rollback`, or re-run the tag commands the script printed |
| The new revision migrated the schema | Restore the pre-update dump (section 6), then roll the images back to the revision that matches it |

PostgreSQL's data lives in the host directory set by `POSTGRES_DATA_PATH`, not in a named volume,
so neither an update nor `docker compose down` touches it (section 6).

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

### Resetting the pgAdmin login

Because the account is stored in the `pgadmin_data` volume when it is first created, a password
that was changed in `.env` afterwards will not work. Reset it in place, which keeps pgAdmin's own
settings, saved servers and preferences:

```bash
docker compose exec pgadmin /venv/bin/python3 /pgadmin4/setup.py update-user \
  "$PGADMIN_DEFAULT_EMAIL" --password '<new-password>' --role Administrator
```

The change takes effect immediately; no restart is needed. Deleting the `pgadmin_data` volume also
works but discards those settings — either way the `pgadmin-config` service re-renders
`servers.json` and `.pgpass` on the next `docker compose up -d`, so the database connection comes
back on its own.

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

### What pgAdmin stores, and what that means

- **The database password sits on disk in plain text.** `.pgpass` in the `pgadmin_data` volume holds
  `POSTGRES_PASSWORD` so the pre-configured server connects without prompting. Anyone who can read
  that volume, or a copy of it, has a database credential — the same one the backend uses. Treat the
  volume with the same care as `.env`.
- **The connection is not pinned to TLS.** `servers.json` sets `sslmode: prefer`, which uses TLS if
  the server offers it and falls back to plain text otherwise. Inside the Compose network neither
  applies; it matters only if a pgAdmin server is repointed at a database across a network.
- **There is no pgAdmin master password** (`PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False`), so
  stored credentials are not encrypted with one. Access control is Cloudflare Access plus pgAdmin's
  own login, and nothing else — which is why the Zero Trust policy below should stay narrow.
- pgAdmin shares the Compose network with the database, so it can reach it freely. Treat it as an
  administrative surface, not a general-purpose SQL console for production.

Creating and downloading dumps through the UI is covered in section 6.

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

## 6. Backups and recovery

The database is the only stateful part of this stack, so backing it up is the whole story: the
images can be rebuilt, `.env` can be re-created, and the data directory is only useful with its
matching PostgreSQL version.

### Everyday use

```bash
make backup          # dump now, rotate old dumps
make restore FILE=backups/opencw_<date>.sql.gz
```

`backup.sh` writes a timestamped plain-SQL dump into `backups/`, verifies it with `gzip -t` and a
non-empty size check, writes a companion `pg_dumpall --globals-only` dump into `backups/globals/`
for roles and grants, and rotates down to the newest 14 (`--keep N`, or `$BACKUP_RETENTION`).
`restore.sh` takes a pre-restore backup, requires you to type the database name before it drops
anything, recreates the database, loads the dump in a single transaction, and reports how many
tables it found afterwards. Flags, exit codes and the safety model are in
[scripts/README.md](scripts/README.md).

### Keeping copies off the host

Dumps in `backups/` protect you from a bad migration, not from losing the host. For that, point
them at storage that is not the machine's own disk — a mounted volume, another server, or object
storage:

```bash
scripts/backup.sh --dir /mnt/backups
```

or set `BACKUP_DIR` in the environment (the scripts, not `.env`) to make it the default. Between
the nightly schedule and the destination, you are choosing the RPO: a nightly dump means losing up
to a day, running it every 15 minutes means losing up to 15 minutes. `make status` warns when the
newest dump is more than 7 days old, which catches a cron job that has quietly stopped.

### Restoring

`restore.sh` is the supported path because it is the one that protects the running database. The
raw equivalent, if you need to do it by hand, keeps the same guarantees:

```bash
set -o pipefail
# 1. Take a backup of the current state first — dropping the database is irreversible.
# 2. Then recreate and load, as one transaction against a fresh database:
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" --if-exists --force "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$POSTGRES_DB"'
gunzip -c backups/opencw_<date>.sql.gz | docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 --single-transaction -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
# 3. Restart the backend so its connection pool reconnects:
docker compose restart backend
```

By default `restore.sh` drops and recreates the database. `--append` applies the dump on top of the
existing schema instead — the one mode that writes into data you already have. Restoring a `globals`
dump (roles and grants) is separate and best-effort: `scripts/restore.sh --globals`.

### Rehearsing a restore

An untested dump is a hope. Rehearse by loading the newest one into a scratch database, which never
touches the live data:

```bash
docker compose exec -T db sh -c 'createdb -U "$POSTGRES_USER" opencw_rehearsal'
gunzip -c backups/opencw_<date>.sql.gz | docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 --single-transaction -U "$POSTGRES_USER" -d opencw_rehearsal'
echo "select count(*) from pg_tables where schemaname = 'public'" | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d opencw_rehearsal -At'
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" opencw_rehearsal'
```

The table count is the point of the exercise: it should be in the same range as the live database,
not zero. Do this after any change to the backup schedule or a database version upgrade.

`restore.sh --append` is not a rehearsal tool: it applies a dump on top of the existing schema of the
**live** database, for when you want to add rows rather than replace the database.

### What the data directory is, and is not

The root Compose configuration bind-mounts the host directory set by `POSTGRES_DATA_PATH` at
`/var/lib/postgresql` in the container. `example.env` sets it to `/data/postgres`; Compose falls
back to `./data/postgres` if it is unset. PostgreSQL stores its cluster under
`/var/lib/postgresql/18/docker`. This is a host path, not a named Docker volume, so
`docker compose down -v` does not touch it.

Before an image upgrade, a consistent filesystem snapshot of that directory, taken while PostgreSQL
is stopped, is a useful second line of defence — or follow the storage provider's documented
procedure for an application-consistent snapshot. A raw copy of a live data directory is **not** a
backup: it can be torn, and it only restores into the same PostgreSQL version.

### Through the pgAdmin UI

1. In the tree, right-click the `opencw` database → *Backup…*.
2. Give the file a name (for example `opencw-<date>.dump`), pick the *Custom* format (compressed,
   restorable with `pg_restore`) or *Plain*, then click *Backup*. Progress and logs appear on the
   *Processes* tab.
3. *Tools → Storage Manager* → select the file → *Download*. It lands in your browser's downloads
   folder.

The pgAdmin image ships PostgreSQL client tools 13–18 and defaults to the v18 binaries, matching
the `postgres:18.6-alpine3.23` server, so `pg_dump`/`pg_restore` run without version-mismatch
errors. Restoring is the reverse: upload the dump with the Storage Manager, then right-click the
database → *Restore…*. Keep in mind that a dump taken this way lands in the browser's downloads
folder, not in `backups/`, so it is outside the retention policy and outside a restore rehearsal.

## 7. Monitoring, logs and reboots

### Health checks

`scripts/status.sh` is the check to schedule. It probes `/v1/health`, the frontend root and
pgAdmin's `/misc/ping`, runs `pg_isready` inside `db`, validates `.env`, and exits non-zero when
something is wrong — so anything that understands an exit code can use it directly:

```bash
make status
scripts/status.sh --skip-disk      # cheap enough for a five-minute cron (see scripts/README.md)
```

It also reports the two things that are easy to miss: how old the newest backup is (warning past
seven days) and how much disk the stack is using.

### Logs

Everything goes to Docker's logging driver:

```bash
docker compose logs -f backend          # or db, frontend, pgadmin, cloudflared
docker compose logs --since 1h backend
```

No rotation is configured, so container logs grow in Docker's data root until something truncates
them. On a long-running host, cap them — per service in `docker-compose.yaml`, or once for the
whole daemon in `/etc/docker/daemon.json`, for example a 10 MB maximum with three retained files —
then `docker compose up -d` to recreate the containers with the new setting.

The database reports the settings it chose at start-up, which is the first thing to read when
something about performance changed:

```bash
docker compose logs db | grep opencw-pg-tune
```

### Reboots

Every long-running service uses `restart: unless-stopped`, so the stack returns by itself after a
reboot — as long as the Docker daemon starts at boot, which is worth confirming once:

```bash
systemctl is-enabled docker
```

`pgadmin-config` is deliberately `restart: "no"`: it is a one-shot renderer that runs on
`docker compose up -d`. After a reboot pgAdmin starts from the volume it already has, and the files
are re-rendered the next time you bring the stack up. If you changed `PGADMIN_*` or
`POSTGRES_PASSWORD` in `.env` and want them applied, run `docker compose up -d` instead of waiting
for a restart.

After a host has come up, `make status` tells you whether it is actually serving.

## 8. Secrets and rotation

Everything secret lives in root `.env`, in plain text. It is git-ignored; keep it readable only by
the operator (`chmod 600 .env`). The scripts parse it and never source it, so a value containing
spaces cannot turn into a command.

| Secret | Used by | Rotating it |
|--------|---------|-------------|
| `POSTGRES_PASSWORD` | the backend's connection pool, pgAdmin's `.pgpass`, and any saved pgAdmin server | Rotate the role, `.env` and pgAdmin's saved copy together |
| `JWT_SECRET` | the backend signs and verifies access tokens with it | Every access and refresh token becomes invalid; users sign in again |
| `RESEND_API_KEY` | transactional email only | Nothing else; `docker compose up -d backend` |
| `PGADMIN_DEFAULT_PASSWORD` | the pgAdmin login, only when its configuration database is first created | Editing `.env` afterwards has no effect — reset it in place (section 5) |

To rotate the database password, use psql's own prompt so the value does not land in your shell
history or the server log:

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
# then, at the psql prompt:  \password opencw
```

Then update `POSTGRES_PASSWORD` in `.env`, run `docker compose up -d` so `pgadmin-config` re-renders
`.pgpass` and the backend picks up the new credential, and re-enter the password in pgAdmin if you
had ticked *Save password*. The old password keeps working until the role is changed, so the order
above is safe to follow at your own pace.

`JWT_SECRET` is the easy one: a new value plus `docker compose up -d backend`.

## 9. Stopping and removing

Stop the stack without touching data:

```bash
docker compose down
```

`docker compose down -v` removes the `pgadmin_data` volume but **not** the database, because the
database is a host bind mount rather than a named volume.

The data path is set in `.env`:

```dotenv
POSTGRES_DATA_PATH=/data/postgres
```

Erasing the database is irreversible, so do it deliberately:

1. Stop the stack: `docker compose down`.
2. Resolve the actual path. `example.env` sets `POSTGRES_DATA_PATH=/data/postgres`, while an unset
   value makes Compose use `./data/postgres` inside the checkout — those are different directories,
   and only one of them exists on your host.
3. Check what you are about to delete: `ls -la <path>`. The directory should contain `PG_VERSION`
   and a `base/` subdirectory, which is what distinguishes a PostgreSQL cluster from any other
   directory of the same name.
4. Remove it, knowing that the only way back is a dump you keep elsewhere (section 6).

## Operational scripts

The scripts in `scripts/` are the source of truth; the `Makefile` only forwards to them. All of
them are safe to run repeatedly. [scripts/README.md](scripts/README.md) has task-oriented guidance,
the safety model, cron examples and troubleshooting.

| Script | Make target | Purpose |
|--------|-------------|---------|
| `scripts/check-env.sh` | `make check` | Validate `.env`, reporting every problem at once |
| `scripts/deploy.sh` | `make deploy` | Bootstrap `.env`, build, start, wait for health |
| `scripts/update.sh` | `make update` | Snapshot, back up, move revision, rebuild, verify |
| `scripts/backup.sh` | `make backup` | Dump the database and rotate old dumps |
| `scripts/restore.sh` | `make restore` | Restore a dump (recreates the database by default) |
| `scripts/status.sh` | `make status` | Health, versions, backups and disk usage |

`--help` works on every script. The scripts that change something also accept `--dry-run` (print the
commands instead of running them) and `--yes` (skip confirmation prompts); `check-env.sh` and
`status.sh` are read-only and deliberately reject both. The complete flag list per script is in
[scripts/README.md](scripts/README.md).

Two properties worth remembering: `.env` is parsed and never sourced, and `status.sh` is safe to
schedule because it only reads — it exits non-zero when the stack is unhealthy, which is what makes
it usable as a monitoring check. [scripts/README.md](scripts/README.md) documents the safety model
behind both.

## PostgreSQL resource tuning

PostgreSQL is not configured for one fixed server size. `db/tune.sh` runs as the `db` service's
entrypoint, works out how much memory and how many CPUs the container actually has, derives the
server settings from that, logs what it chose and why, and then hands off to the image's own
entrypoint — so `initdb`, `pg_hba.conf` and `/docker-entrypoint-initdb.d` behave exactly as they do
upstream.

[db/README.md](db/README.md) is the full guide: every variable, worked examples, how to check what
was chosen, and a troubleshooting table. What follows is the short version.

Read the derived settings from the container log:

```bash
docker compose logs db | grep opencw-pg-tune
```

Memory budget, first source that yields a value wins:

| Order | Source |
|-------|--------|
| 1 | `POSTGRES_MEMORY_LIMIT`, which also becomes the container's `mem_limit` |
| 2 | cgroup v2 `memory.max` |
| 3 | cgroup v1 `memory.limit_in_bytes` |
| 4 | `POSTGRES_HOST_MEMORY_SHARE` percent (default `50`) of `/proc/meminfo` `MemTotal` |

The CPU budget follows the same idea: `POSTGRES_CPU_LIMIT` (also the container's `cpus`), then
cgroup v2 `cpu.max`, cgroup v1 `cpu.cfs_quota_us`, `cpuset.cpus`, and finally `nproc`.

Order 4 exists because a container with no memory limit sees the whole machine. On a host that
runs anything else, set `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` in `.env` so PostgreSQL
sizes itself against its own share.

### Declaring the budget on an LXC or nested-container host

`/proc/meminfo` is not namespaced. LXC masks it for the container it manages, but not for the
Docker containers running inside that container, so `MemTotal` in the `db` container is the
**physical host's** memory. Measured on this project's test LXC, which is configured with 4 GB:

| Observed from | `MemTotal` |
|---------------|------------|
| The LXC itself | 4 GiB |
| The Docker daemon on that LXC | 4 GiB |
| Inside the `db` container | 31 GiB |

No cgroup limit is visible either — the container has none of its own — so order 4 is the only
source left and it is wrong by nearly eight times. That matters because the derived
`effective_cache_size` and `work_mem` would then describe a machine the database cannot use, and
`shared_buffers` alone would claim most of the container's real allowance.

So on an LXC or nested-container host, declare the budget. For a 4 GB LXC that also runs the rest
of this stack, 3 GB leaves the other services headroom:

```dotenv
POSTGRES_MEMORY_LIMIT=3g
POSTGRES_CPU_LIMIT=4
```

That gives `shared_buffers` 768 MB, `work_mem` 10 MB and four parallel workers, and makes Docker
enforce the ceiling rather than leaving it to chance. When no budget is declared, the tuner caps
this fallback at 4 GiB and logs a warning saying so, rather than sizing for a machine it cannot
see.

The settings that follow from the budget (`B` MiB) and the CPU count (`C`):

| Setting | Derived from |
|---------|--------------|
| `shared_buffers` | `B / 4`, clamped to 128 MB – 8 GB |
| `effective_cache_size` | `B * 3 / 4` |
| `maintenance_work_mem` | `B / 16`, clamped to 64 MB – 2 GB |
| `work_mem` | `B / (3 * max_connections)`, clamped to 1 MB – 64 MB |
| `wal_buffers` | `shared_buffers / 32`, clamped to 1 MB – 16 MB |
| `max_wal_size` / `min_wal_size` | `B / 8`, clamped to 1 GB – 8 GB, and a quarter of that |
| `max_worker_processes`, `max_parallel_workers` | `C`, clamped to 2 – 16 |
| `max_parallel_workers_per_gather`, `max_parallel_maintenance_workers` | `C / 2` |
| `max_connections` | `POSTGRES_MAX_CONNECTIONS`, default `100` |

Five settings describe the disk and the query mix rather than the machine size, so they are fixed
instead of derived: `checkpoint_completion_target=0.9`, `default_statistics_target=100`,
`random_page_cost=1.1`, `effective_io_concurrency=200` and `huge_pages=off`. The last two assume
SSD/NVMe storage and should be higher on spinning disks. Because they are passed on the command
line like everything else, change them with `POSTGRES_TUNE_EXTRA` — editing them in
`postgresql.conf` would have no effect.

Two things worth knowing:

- `shm_size` cannot be derived, because Compose fixes it when the container is created. It comes
  from `POSTGRES_SHM_SIZE` (default `2gb`), and the tuner warns at start-up when the derived
  parallelism could need more than is available. Keep it at or below `POSTGRES_MEMORY_LIMIT`:
  `/dev/shm` is charged to the container's memory limit, so an oversized value surfaces as an
  out-of-memory kill under parallel queries rather than as a start-up error. `make check` warns
  about that combination.
- These values arrive as `postgres` command-line arguments, so they are not written to
  `postgresql.conf` and they take precedence over `ALTER SYSTEM`. Changing one of them through
  pgAdmin will not survive a restart. Use `POSTGRES_TUNE_EXTRA` (for example
  `POSTGRES_TUNE_EXTRA=-c work_mem=32MB`) or change the budget instead, and
  `POSTGRES_TUNE_DISABLE=1` to turn the derived values off entirely.

The same script backs the `db` service in `backend/docker-compose.yaml`, so local development runs
on settings derived from the Docker VM rather than on PostgreSQL's defaults for a much smaller
machine.

## Environment variable reference

| Variable          | Required | Description |
|-------------------|----------|-------------|
| `POSTGRES_USER`   | yes      | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | yes    | PostgreSQL superuser password |
| `POSTGRES_DB`     | yes      | Database name |
| `DB_PORT` | no | Host port for the database, default `5432`, published on every interface |
| `POSTGRES_DATA_PATH` | no | Host directory bind-mounted at `/var/lib/postgresql`; `example.env` sets `/data/postgres`, Compose fallback is `./data/postgres`. |
| `POSTGRES_MEMORY_LIMIT` | no | Memory budget for the `db` service, e.g. `2g` or `512mb`. Also the container's `mem_limit`; `0` means no limit. Must stay above `POSTGRES_SHM_SIZE`. |
| `POSTGRES_CPU_LIMIT` | no | CPU budget for the `db` service, e.g. `2` or `1.5`. Also the container's `cpus`; `0` means no limit. |
| `POSTGRES_SHM_SIZE` | no | Size of `/dev/shm` for parallel queries, default `2gb`. Compose fixes it when the container is created, so the tuner can only warn about it. |
| `POSTGRES_MAX_CONNECTIONS` | no | Server-side connection ceiling, default `100`. Keep it above `DB_MAX_OPEN_CONNS` plus the pgAdmin and backup connections; it also divides `work_mem`. |
| `POSTGRES_HOST_MEMORY_SHARE` | no | Percentage of host memory the database may assume when no container limit is detected, default `50`. |
| `POSTGRES_TUNE_DISABLE` | no | `1` skips the derived settings and uses the image's own defaults. |
| `POSTGRES_TUNE_EXTRA` | no | Extra server arguments, appended last so they win, e.g. `-c work_mem=32MB`. |
| `PGADMIN_DEFAULT_EMAIL` | yes | Login for the pgAdmin web UI. An email address, not a PostgreSQL role. Set once: pgAdmin derives its storage paths from it. |
| `PGADMIN_DEFAULT_PASSWORD` | yes | Password for the pgAdmin web UI login, read when pgAdmin's configuration database is first created. |
| `PGADMIN_PORT` | no | Host port for the pgAdmin UI, published on `127.0.0.1` only, default `5050`. |
| `JWT_SECRET`      | yes      | Base64-encoded secret (≥ 32 raw bytes). Backend exits on startup if missing. |
| `RESEND_API_KEY`  | yes      | Resend API key, declared `required:"true"` in `backend/internal/configs/config.go`. The backend exits on startup when it is empty, so a blank value crash-loops the container. |
| `RESEND_FROM_EMAIL` | yes    | From address for transactional email, e.g. `OpenCW <no-reply@example.com>`. Same startup validation as `RESEND_API_KEY`. |
| `CORS_ORIGINS`    | yes      | Comma-separated allowed browser origins, e.g. `https://opencw.example.com` |
| `PUBLIC_API_BASE` | yes      | Browser-visible backend URL, baked into the frontend at build time, e.g. `https://api.opencw.example.com/v1` |
| `READ_TIMEOUT` | no | Backend request read timeout (Go duration), default `15s` |
| `READ_HEADER_TIMEOUT` | no | Backend header read timeout, default `5s` |
| `WRITE_TIMEOUT` | no | Backend response write timeout, default `30s` |
| `IDLE_TIMEOUT` | no | Backend keep-alive idle timeout, default `120s` |
| `SHUTDOWN_TIMEOUT` | no | Graceful shutdown timeout, default `20s` |
| `DB_MAX_OPEN_CONNS` | no | Backend DB max open connections. The backend defaults to `25`; `example.env` ships `30`. |
| `DB_MAX_IDLE_CONNS` | no | Backend DB max idle connections, default `5` |
| `DB_CONN_MAX_LIFETIME` | no | Backend DB connection max lifetime, default `30m` |
| `DB_CONN_MAX_IDLE_TIME` | no | Backend DB connection max idle time, default `5m` |
| `CLOUDFLARED_TUNNEL_TOKEN` | no | Cloudflare Tunnel token. `cloudflared` always starts with the stack; an empty token makes it restart-loop, which `make check` warns about |
| `CLOUDFLARED_PROTOCOL` | no | Connector transport protocol (`quic` or `http2`), default `quic` |
