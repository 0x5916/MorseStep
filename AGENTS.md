# OpenCW / MorseStep Repository Instructions for Coding Agents

This repository contains the MorseStep (formerly OpenCW) sound-first Morse code training platform.
All agents must adhere to the bounded-packet operating model and repository rules defined here.

## 1. Repository Map

- `frontend/`: Static SvelteKit 5 + TypeScript web application, Tailwind CSS v4, Paraglide i18n, `@sveltejs/adapter-static`.
- `backend/`: Go 1.25 REST API (`cmd/api-server/main.go`, `internal/` handlers, models, router, middleware).
- `scripts/`: Operational bash automation (`deploy.sh`, `update.sh`, `backup.sh`, `restore.sh`, `check-env.sh`, `status.sh`).
- `db/`: PostgreSQL configuration and auto-tuning (`tune.sh`).
- `Makefile`: Entry points delegating to `scripts/` targets.
- `docker-compose.yaml`: Full production/staging stack (db, backend, frontend, cloudflared).

## 2. Commands by Subsystem

### Frontend (requires Node 26)

Ensure Node 26 is on your PATH (e.g. `export PATH="/opt/homebrew/opt/node/bin:$PATH"`):

- `npm run verify`: Full verification gate (messages, SEO, svelte-check, ts-check scripts, Vitest).
- `npm run test`: Vitest unit tests for domain math, session machines, audio engine, sync.
- `npm run lint`: Prettier check + ESLint.
- `npm run format`: Prettier write.
- `npm run build`: Static production prerender build into `frontend/build/`.
- `npm run dev`: Local Vite development server with HMR.

### Backend (Go 1.25+)

- `go test ./...`: Run backend unit and integration test suite.
- `go vet ./...`: Run Go static analysis.

### Operational Scripts

- `make check`: Validate `.env` configuration.
- `make status`: Health check, container versions, disk usage.

## 3. Governance and Safety Boundaries

1. **No Framework Migrations:** Maintain the existing SvelteKit 5 + static adapter and Go backend. Do not migrate to other frameworks or runtimes.
2. **No Destructive Git:** Never run `git push --force`, `git reset --hard` across uncommitted work, or clean untracked files without confirmation.
3. **Bounded Packets:** Implement one discrete task packet per session (typically <400 LOC changed, targeted tests, specific acceptance criteria).
4. **Backend / API Approval (Risk R2/R3):** Do not alter backend database schemas, endpoints, authentication semantics, or deployment configs without an approved API specification and explicit authorization.
5. **No Blind Dependency Additions:** Do not introduce external dependencies without approval.
6. **Required Verification Evidence:** Never declare completion without capturing command exit codes, test counts, and `git status --short`.
