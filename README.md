# OpenCW

OpenCW is a full-stack Morse code training platform with:

- Go backend API (Gin + GORM)
- SvelteKit frontend
- PostgreSQL database
- Docker Compose orchestration

## Project Structure

- [backend](backend)
- [frontend](frontend)
- [db](db) — PostgreSQL tuning guide for the `db` service
- [scripts](scripts) — operational scripts
- [api_test](api_test)
- [docker-compose.yaml](docker-compose.yaml)
- [example.env](example.env)
- [DEPLOYMENT.md](DEPLOYMENT.md)

## Quick Start (Docker)

1. Copy environment template:

   cp example.env .env

2. Generate JWT secret:

   openssl rand -base64 32

3. Put the generated value into .env as JWT_SECRET.

4. Set the pgAdmin login in .env (`PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`). This
   login is for the admin UI only; it is not a PostgreSQL role.

5. Start all services:

   docker compose up -d --build

6. Open the app:

   http://localhost:3000

## Services

- Frontend: http://localhost:3000
- Backend API base: http://localhost:8080/v1
- Health check: http://localhost:8080/v1/health
- pgAdmin 4 (database admin UI): http://127.0.0.1:5050
- PostgreSQL: `localhost:${DB_PORT:-5432}`, sized automatically at start-up — see [DEPLOYMENT.md](DEPLOYMENT.md)

## Common Commands

Day-to-day operations go through the `make` targets, which wrap the scripts in
[scripts](scripts) with environment validation, backups, and health checks. Run `make` on its own
for the full list.

| Task | Command |
|------|---------|
| Validate `.env` | `make check` |
| First-time install | `make deploy` |
| Update to the latest revision | `make update` |
| Update to a specific ref | `make update REF=v1.2.0` |
| Preview what an update would do | `make update DRY_RUN=1` |
| Back up the database | `make backup` |
| Back up, keeping 30 dumps | `make backup KEEP=30` |
| Restore a backup | `make restore FILE=backups/opencw_<date>.sql.gz` |
| Health, versions and disk usage | `make status` |

Each script also runs standalone and documents its own options, for example
`scripts/restore.sh --help`. See [scripts/README.md](scripts/README.md) for the full guide, including
the safety model, cron examples and troubleshooting.

The underlying `docker compose` commands still work:

Start / rebuild:

docker compose up -d --build

View logs:

docker compose logs -f

Restart backend only:

docker compose up -d backend

Restart the database admin UI only:

docker compose up -d pgadmin

Stop without removing data:

docker compose down

Remove the pgAdmin volume (the database is a bind mount and is **not** affected — see
[DEPLOYMENT.md](DEPLOYMENT.md) section 7):

docker compose down -v

## Environment Variables

See [example.env](example.env) for the full list. Required variables:

- POSTGRES_USER
- POSTGRES_PASSWORD
- POSTGRES_DB
- JWT_SECRET (must be base64)
- RESEND_API_KEY
- RESEND_FROM_EMAIL
- CORS_ORIGINS
- PUBLIC_API_BASE
- PGADMIN_DEFAULT_EMAIL (pgAdmin login, not a database role)
- PGADMIN_DEFAULT_PASSWORD

## API Testing

API request collections and environment files are in [api_test](api_test).

## Production Deployment

Use [DEPLOYMENT.md](DEPLOYMENT.md) for production setup, reverse proxy, backup, and update
procedures. `make deploy` and `make update` automate the first two sections of that document.

pgAdmin is published on `127.0.0.1` only. Public access goes through the Cloudflare tunnel at
`https://pgadmin.opencw.net`, guarded by a Zero Trust Access policy — see DEPLOYMENT.md.

## Notes

- The frontend uses PUBLIC_API_BASE at build time. If this value changes, rebuild the frontend image.
- If browser requests are blocked by CORS, ensure CORS_ORIGINS contains the exact frontend origin you open in the browser.
- PostgreSQL derives its settings at start-up from the memory and CPU the `db` container actually has, via [db/tune.sh](db/tune.sh), instead of using values fixed for one machine size. Give it an explicit budget with `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` in `.env`; what it chose is printed in `docker compose logs db`. Full guide: [db/README.md](db/README.md); summary: the resource tuning section of [DEPLOYMENT.md](DEPLOYMENT.md).
