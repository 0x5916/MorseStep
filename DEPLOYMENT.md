# Production Deployment

OpenCW is deployed as three Docker containers orchestrated by Docker Compose:

| Service    | Image                       | Port |
|------------|-----------------------------|------|
| `db`       | `postgres:18.6-alpine3.23`  | —    |
| `backend`  | built from `./backend`      | 8080 |
| `frontend` | built from `./frontend`     | 3000 |

Optional profile:

| Service       | Image                         | Port |
|---------------|-------------------------------|------|
| `cloudflared` | `cloudflare/cloudflared:latest` | —  |

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
```

### Generating a JWT secret

```bash
openssl rand -base64 32
```

The value must be base64-encoded. The backend decodes it at startup and exits if it is missing or malformed.

## 2. Build and start

```bash
docker compose up -d --build
```

Compose will:
1. Pull `postgres:18.6-alpine3.23` and start the database.
2. Wait for the database healthcheck to pass.
3. Build and start the backend (Go, distroless image, `GIN_MODE=release`).
4. Build and start the frontend (SvelteKit Node adapter, `NODE_ENV=production`).

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

Then start with the tunnel profile:

```bash
docker compose --profile tunnel up -d --build
```

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

Compose will rebuild changed images and recreate only the affected containers. PostgreSQL's data persists in the host directory configured by `POSTGRES_DATA_PATH`; it is not a named Compose volume and is not removed by `docker compose down`.

## 5. Backups

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

## 6. Stopping / removing

Stop without removing data:

```bash
docker compose down
```

`docker compose down -v` does not delete the bind-mounted database data. To erase it, stop the stack and manually remove the directory configured by `POSTGRES_DATA_PATH` (irreversible).

The data path can be set in `.env`:

```dotenv
POSTGRES_DATA_PATH=/data/postgres
```

## Environment variable reference

| Variable          | Required | Description |
|-------------------|----------|-------------|
| `POSTGRES_USER`   | yes      | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | yes    | PostgreSQL superuser password |
| `POSTGRES_DB`     | yes      | Database name |
| `POSTGRES_DATA_PATH` | no | Host directory bind-mounted at `/var/lib/postgresql`; `example.env` sets `/data/postgres`, Compose fallback is `./data/postgres`. |
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
