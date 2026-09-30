# PostgreSQL tuning

`db/tune.sh` is the `db` service's entrypoint. It works out how much memory and how many CPUs the
container actually has, derives the PostgreSQL settings from that, logs what it chose, and then hands
off to the image's own `docker-entrypoint.sh` with the derived `-c` flags appended. `initdb`,
`pg_hba.conf` and `/docker-entrypoint-initdb.d` behave exactly as they do upstream — this only
supplies configuration arguments.

Nothing here needs to be run by hand. The settings used to be hardcoded for one 8 GB / 4 vCPU
machine; they are now derived, and every run says what they were derived from.

- Variables and defaults: [example.env](../example.env)
- Deployment context and the env reference table: [DEPLOYMENT.md](../DEPLOYMENT.md)
- `.env` validation: [scripts/check-env.sh](../scripts/check-env.sh)

## Requirements

- Docker with Compose v2. Tested against Docker 26.1.5 and 29.4.0 on cgroup v2.
- No dependencies inside the image: the script is POSIX `sh` and uses only busybox tools.
- The cgroup v1 branches exist for older hosts but have not been exercised — the project's test
  hosts are all cgroup v2.

## Quick start

| Where the database runs | What to do |
|---|---|
| A host whose whole memory belongs to this stack | Nothing. It sizes itself. |
| An LXC, or any host that runs other things | Set `POSTGRES_MEMORY_LIMIT` and `POSTGRES_CPU_LIMIT` in `.env`. On an LXC this is required, not advisory — see [Nested containers](#nested-containers-and-lxc). |
| Local development (`backend/`) | Nothing. It sizes itself from the Docker VM. |

```dotenv
# .env — for a 4 GB LXC that also runs the rest of this stack
POSTGRES_MEMORY_LIMIT=3g
POSTGRES_CPU_LIMIT=4
```

Both values also become the container's `mem_limit` and `cpus`, so Docker enforces the ceiling
instead of you hoping the database stays inside it. `0` means "no limit".

## How the budget is chosen

Memory, first source that yields a value wins:

| Order | Source | Notes |
|---|---|---|
| 1 | `POSTGRES_MEMORY_LIMIT` | Explicit. Also the container's `mem_limit`. |
| 2 | cgroup v2 `/sys/fs/cgroup/memory.max` | Set when the container has its own limit. |
| 3 | cgroup v1 `memory.limit_in_bytes` | Legacy hosts. |
| 4 | `POSTGRES_HOST_MEMORY_SHARE` percent of `/proc/meminfo` `MemTotal` | Default 50. Capped at 4 GiB. |

The share applies **only** in order 4, never on top of an explicit or cgroup limit, so declaring a
limit never gets discounted twice.

CPUs, same idea: `POSTGRES_CPU_LIMIT`, then cgroup v2 `cpu.max` (a fractional quota like
`--cpus=1.5` is rounded up), then cgroup v1 CFS quota, then `cpuset.cpus.effective` (sparse lists
such as `0,3,7,13` are counted correctly), then `nproc`.

If neither a limit nor a cgroup value is available, the run is *guessed* — and order 4 is the only
place the script is willing to guess wrong, which is why it is capped and warned about.

## What it sets

From the budget `B` MiB, with `max_connections` at its default of 100:

| Setting | Derived from | Clamp |
|---|---|---|
| `shared_buffers` | `B / 4` | 128 MB – 8 GB |
| `effective_cache_size` | `B * 3 / 4` | at least `shared_buffers`, at most 16 GB |
| `maintenance_work_mem` | `B / 16` | 64 MB – 2 GB |
| `work_mem` | `B / (3 * max_connections)` | 1 MB – 64 MB |
| `wal_buffers` | `shared_buffers / 32` | 1 MB – 16 MB |
| `max_wal_size` | `B / 8` | 1 GB – 8 GB |
| `min_wal_size` | `max_wal_size / 4` | 256 MB – 2 GB |
| `max_connections` | `POSTGRES_MAX_CONNECTIONS` | 10 – 1000, default 100 |
| `max_worker_processes`, `max_parallel_workers` | CPU count | 2 – 16 |
| `max_parallel_workers_per_gather`, `max_parallel_maintenance_workers` | half the CPU count | 1 – `max_parallel_workers` |

`max_connections` is the one setting that is **not** resource-derived: it is a demand figure, so it
defaults to 100 and only divides `work_mem`.

Deliberately left alone, because they describe the disk and the query mix rather than the machine
size:

| Setting | Value | Why |
|---|---|---|
| `checkpoint_completion_target` | 0.9 | PostgreSQL's recommended default. |
| `default_statistics_target` | 100 | PostgreSQL's own default. |
| `random_page_cost` | 1.1 | Assumes SSD/NVMe storage. Raise it for spinning disks. |
| `effective_io_concurrency` | 200 | Same assumption: fast random I/O. |
| `huge_pages` | off | The host has to reserve huge pages for the container first. |

These five are still passed on the command line, so changing them means `POSTGRES_TUNE_EXTRA`, not
`postgresql.conf`.

### Worked examples

`max_connections=100`, so `work_mem` is `B / 300`:

| Budget | `shared_buffers` | `effective_cache_size` | `maintenance_work_mem` | `work_mem` | `wal_buffers` | `max_wal_size` | `min_wal_size` |
|---|---|---|---|---|---|---|---|
| 512 MiB | 128 MB | 384 MB | 64 MB | 1747 kB | 4 MB | 1 GB | 256 MB |
| 1 GiB | 256 MB | 768 MB | 64 MB | 3495 kB | 8 MB | 1 GB | 256 MB |
| 2 GiB | 512 MB | 1536 MB | 128 MB | 6990 kB | 16 MB | 1 GB | 256 MB |
| 3 GiB | 768 MB | 2304 MB | 192 MB | 10485 kB | 16 MB | 1 GB | 256 MB |
| 4 GiB | 1024 MB | 3072 MB | 256 MB | 13981 kB | 16 MB | 1 GB | 256 MB |
| 8 GiB | 2048 MB | 6144 MB | 512 MB | 27962 kB | 16 MB | 1 GB | 256 MB |

Worker counts depend only on the CPU count: 1 → 2/2/1/1, 2 → 2/2/1/1, 4 → 4/4/2/2, 8 → 8/8/4/4,
16 → 16/16/8/8, 32 or more → 16/16/16/16.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `POSTGRES_MEMORY_LIMIT` | `0` (no limit) | Memory budget, e.g. `3g`, `512mb`, or a byte count. Also the container's `mem_limit`. |
| `POSTGRES_CPU_LIMIT` | `0` (no limit) | CPU budget, e.g. `4` or `1.5`. Also the container's `cpus`. |
| `POSTGRES_SHM_SIZE` | `2gb` | `/dev/shm` for parallel queries. Compose fixes it at container creation, so the tuner can only warn about it. |
| `POSTGRES_MAX_CONNECTIONS` | `100` | Server-side connection ceiling. Keep it above `DB_MAX_OPEN_CONNS` plus the pgAdmin and backup connections. |
| `POSTGRES_HOST_MEMORY_SHARE` | `50` | Percentage of `MemTotal` to assume when no limit is set. Only used in the last-resort path. |
| `POSTGRES_TUNE_DISABLE` | `0` | `1` skips the derived values and uses the image's defaults. |
| `POSTGRES_TUNE_EXTRA` | empty | Extra server arguments, appended last so they win, e.g. `-c work_mem=32MB`. |

## Check what it decided

The container log states the detection source and every derived value with its rule:

```bash
docker compose logs db | grep opencw-pg-tune
```

```text
opencw-pg-tune: detected 3072 MiB memory (from POSTGRES_MEMORY_LIMIT=3g) and 4 CPU(s) (from POSTGRES_CPU_LIMIT=4)
opencw-pg-tune:   shared_buffers                   = 768MB (budget / 4, clamped to 128MB..8192MB)
```

Recompute on the spot without restarting anything:

```bash
docker compose exec db sh -c 'sh /usr/local/bin/opencw-pg-tune.sh --print'
```

What the running server actually has:

```bash
echo "select name, setting, coalesce(unit, '') from pg_settings where name in ('shared_buffers','effective_cache_size','maintenance_work_mem','work_mem','wal_buffers','min_wal_size','max_wal_size','max_connections','max_worker_processes','max_parallel_workers','max_parallel_workers_per_gather','max_parallel_maintenance_workers') order by name" \
  | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'
```

Validate `.env` before deploying (`make check` also checks the tuning variables):

```bash
make check
```

## Changing a value

Three levels, in the order to prefer them:

1. **Change the budget** — `POSTGRES_MEMORY_LIMIT` / `POSTGRES_CPU_LIMIT`. Everything scales
   together and stays consistent. This is the right lever when the server needs more or less of
   something as a whole.
2. **Pin one setting** — `POSTGRES_TUNE_EXTRA="-c work_mem=32MB"`. Appended last, so it wins over
   the derived value. Use this when you want one setting off-profile.
3. **Turn it off** — `POSTGRES_TUNE_DISABLE=1` uses the image's own defaults, for comparison or as a
   fallback while debugging.

Two things worth knowing before you tune by hand:

- These values are passed as command-line arguments to `postgres`, so they do **not** appear in
  `postgresql.conf` and they take precedence over `ALTER SYSTEM`. A setting changed through pgAdmin
  is reverted on the next restart; change `POSTGRES_TUNE_EXTRA` or the budget instead.
- Any change is applied by recreating the container (`docker compose up -d db`), not by editing data
  files. Nothing is written into `PGDATA`, so changing the budget never touches the cluster.

## Nested containers and LXC

`/proc/meminfo` is not namespaced. LXC masks it for the container it manages, but **not** for the
Docker containers running inside that container, so `MemTotal` inside `db` is the physical host's
memory. Measured on this project's test LXC, which is configured with 4 GB:

| Observed from | `MemTotal` |
|---|---|
| The LXC itself | 4 GiB |
| The Docker daemon on that LXC | 4 GiB |
| Inside the `db` container | 31 GiB |

No cgroup limit is visible either — that container has none of its own — so order 4 is the only
source left, and it is wrong by nearly eight times. Two consequences:

- The fallback is capped at 4 GiB and logs a warning naming the reason, so an undeclared budget can
  never size the database for a machine it cannot see.
- On such a host, declare the budget. For a 4 GB LXC running this stack, `3g` leaves the other
  services headroom and produces `shared_buffers` 768 MB, `work_mem` 10485 kB and four parallel
  workers, with the cgroup enforced by Docker.

The cap is a judgement call: it trades precision on a large single-level host (where `MemTotal`
really is the container's memory) for safety on nested ones. Declaring the budget removes the guess
entirely.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `WARNING: no container memory limit is set, and /proc/meminfo reports N MiB ... capped at 4096 MiB` | Nested container; `MemTotal` is the host's | Set `POSTGRES_MEMORY_LIMIT` (and `POSTGRES_CPU_LIMIT`) to this container's real share |
| `WARNING: no container memory limit is set, so the budget is 50% of /proc/meminfo MemTotal` | Same path, below the 4 GiB cap | Confirm the figure suits the container, or declare the budget |
| `WARNING: only N MiB of memory is available` | Budget below 512 MiB, settings at their floors | Fine for a test instance; raise the budget for production |
| `WARNING: /dev/shm is N MiB but the derived settings can ask for roughly M MiB` | `POSTGRES_SHM_SIZE` too small for the parallelism | Raise `POSTGRES_SHM_SIZE` (keep it at or below `POSTGRES_MEMORY_LIMIT`), or reduce the worker counts |
| Queries fail with `could not resize shared memory segment` | Same, already happening at runtime | Raise `POSTGRES_SHM_SIZE` |
| `ERROR: cannot find docker-entrypoint.sh` and the container restart-loops | `db/tune.sh` is not mounted, or the image changed | Check `docker compose config` for the mount, and that the file exists at the path Compose resolves |
| `WARNING: POSTGRES_MEMORY_LIMIT='…' is not a size` | Typo in `.env` | `make check` catches this before deploying |
| `FATAL: sorry, too many clients already` | `POSTGRES_MAX_CONNECTIONS` below the real client count | Raise it above `DB_MAX_OPEN_CONNS` plus pgAdmin and backup connections |
| A setting edited in pgAdmin reverts after a restart | Command-line `-c` values beat `ALTER SYSTEM` | Use `POSTGRES_TUNE_EXTRA` |
| Settings look small on a big host | The 4 GiB fallback cap | Declare `POSTGRES_MEMORY_LIMIT` |
| The stack will not start: `port is already allocated` | Something else owns `DB_PORT` | Unrelated to tuning; change `DB_PORT` |

## Design notes

- **Mounted, not built.** `db/tune.sh` is bind-mounted read-only. A derived image would carry no
  RepoDigest, and `scripts/lib/common.sh` treats such images as locally built, which would change
  what `update.sh` snapshots and rolls back.
- **Never fails the container.** Unparseable or absurd input warns and falls back to the image
  defaults, because `restart: unless-stopped` would turn a config typo into a crash loop. The single
  exception is a missing image entrypoint, which is unrecoverable anyway.
- **POSIX `sh`.** It runs before the image entrypoint and must not depend on bash. All arithmetic is
  in whole MiB because POSIX sh has no floating point.
- **Visible by default.** The detection source, every derived value and every fixed setting are
  logged, so nobody has to guess where a number came from.
- **Idempotent.** Nothing is written to `PGDATA`, so a budget change is just a container restart and
  can be reverted the same way.

## This project's hosts

| Host | Configuration | Result |
|---|---|---|
| `pve-104` test LXC (4 GB, 4 vCPU, Docker inside LXC) | `POSTGRES_MEMORY_LIMIT=3g`, `POSTGRES_CPU_LIMIT=4` | 3072 MiB budget, `mem_limit` 3221225472 and `nano_cpus` 4000000000 enforced, `shared_buffers` 768 MB, `work_mem` 10485 kB, workers 4/4/2/2 |
| `pve-104` with nothing declared | — | Warns, caps at 4096 MiB → `shared_buffers` 1024 MB |
| The same box before this change | Hardcoded 8 GB-machine values | `shared_buffers` 1536 MB, `effective_cache_size` 4608 MB, `max_wal_size` 4 GB — i.e. sized for a machine twice its size |
| Local development (`backend/docker-compose.yaml`) | Nothing needed | Sizes itself from the Docker VM; add `POSTGRES_MEMORY_LIMIT` to `backend/.env` if you want it larger |
