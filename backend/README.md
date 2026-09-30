# OpenCW Backend

This folder's `docker-compose.yaml` and `example.env` are for backend development workflows. For production deployment, use the repository root files.

## Build production image

1. Create a runtime env file from the template:

```bash
cp example.env .env
```

2. Set a secure `JWT_SECRET` in base64 format:

```bash
openssl rand -base64 32
```

3. Build the production image:

```bash
docker build -t opencw-backend:latest .
```

4. Run with explicit environment values:

```bash
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e GIN_MODE=release \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e DB_USER=user \
  -e DB_PASSWORD=secret \
  -e DB_NAME=opencw \
  -e JWT_SECRET=<base64-secret> \
  -e RESEND_API_KEY=<resend-api-key> \
  -e RESEND_FROM_EMAIL='OpenCW <onboarding@resend.dev>' \
  opencw-backend:latest
```

## Run app + Postgres with Docker Compose

```bash
docker compose up --build -d
```

Health check endpoint:

```bash
curl http://localhost:8080/v1/health
```

The `db` service derives its PostgreSQL settings from the resources the Docker VM has, and logs
what it chose:

```bash
docker compose logs db | grep opencw-pg-tune
```

To give it a different budget, set `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` in this
folder's `.env`. The full guide is [db/README.md](../db/README.md).

