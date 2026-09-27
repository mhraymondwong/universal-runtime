# universal-runtime

Multi-architecture Docker base runtime for **Laravel 13 + Filament 5** applications, powered by **FrankenPHP / Caddy on PHP 8.4**, published to GitHub Container Registry (GHCR).

This image contains **infrastructure only** — no application code, no `.env` secrets, no Node.js, no database server. Consumer apps mount their code at `/app`; the built-in Caddyfile serves `/app/public` automatically.

This repo also publishes a shared backup image, [`universal-backup`](#universal-backup) — scheduled Postgres + file backups for every app on this stack.

## What's inside

| Component            | Detail                                                        |
| -------------------- | ------------------------------------------------------------- |
| Base                 | `dunglas/frankenphp:php8.4` (FrankenPHP + Caddy + PHP 8.4)        |
| PHP extensions       | `pdo_pgsql`, `pgsql`, `intl`, `gd`, `zip`, `pcntl`, `bcmath`, `opcache`, `redis` |
| Composer             | Latest stable, at `/usr/bin/composer`                         |
| Working directory    | `/app`                                                        |
| Architectures        | `linux/amd64`, `linux/arm64`                                  |
| Web server           | Caddy (FrankenPHP `php_server`) — HTTP or auto-HTTPS via `SERVER_NAME` |

## Image tags

| Tag                 | Produced by                          |
| ------------------- | ------------------------------------ |
| `php8.4`            | Every publish                        |
| `latest`            | Every publish                        |
| `php8.4-vX.Y.Z`     | Pushing git tag `vX.Y.Z`             |
| `php8.4-dev`, `sha-*` | Manual `workflow_dispatch` runs    |

## Publishing the image (maintainer guide)

### 1. Create the GitHub repository

```bash
git init
git add -A
git commit -m "Initial commit"
git remote add origin git@github.com:mhraymondwong/universal-runtime.git
git push -u origin main
```

Or create the repo at github.com first, then push.

### 2. Release a version

```bash
git tag v1.0.0
git push --tags
```

The workflow `.github/workflows/build-publish.yml` builds both architectures, smoke-tests the image (PHP version, all extensions, Composer), then pushes to GHCR. A manual run is also available under **Actions → Build & Publish Runtime Image → Run workflow**.

A `vX.Y.Z` tag is a shared release for the whole repo: it also publishes `universal-backup` as `pg<N>-vX.Y.Z` (see [below](#universal-backup)).

### 3. Make the package public (one-time)

The first publish creates the package as private. To make it public:

1. Go to `https://github.com/mhraymondwong?tab=packages` → select `universal-runtime`.
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public**.
3. Also under **Package settings → Connect repository**, link this repo so the README renders on the package page.

Customers can then pull without authentication:

```bash
docker pull ghcr.io/mhraymondwong/universal-runtime:php8.4
```

## Using the image (customer deployment)

A full working example is in [`examples/docker-compose.yml`](examples/docker-compose.yml). Expected customer layout:

```
docker-compose.yml      # from the deploy kit
.env                    # customer-edited secrets (DB_PASSWORD, APP_KEY, ...)
app/                    # extracted from business-app.tar.gz
```

```yaml
services:
  app:
    image: ghcr.io/mhraymondwong/universal-runtime:php8.4
    restart: unless-stopped
    environment:
      SERVER_NAME: ":80"            # HTTP. Use a domain for auto-HTTPS + publish 443.
      DB_HOST: db
      DB_DATABASE: app
      DB_USERNAME: app
      DB_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ./app:/app                  # mount the business app
    ports:
      - "80:80"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

The example file additionally includes `queue` (`php artisan queue:work`) and `scheduler` (`php artisan schedule:work`) services reusing the same image — recommended for production apps.

### `business-app.tar.gz` expectations

The application tarball is built per-project (separate repo) and must contain:

- Application source code
- `vendor/` — built with `composer install --no-dev --optimize-autoloader`
- Compiled frontend assets (`public/build/`) — built before packaging; there is no Node.js in this image
- **No `.env`** — secrets are supplied via `docker-compose.yml` environment / `.env` file

### After first deploy

```bash
docker compose exec app php artisan key:generate   # or ship APP_KEY in customer .env
docker compose exec app php artisan migrate --force
docker compose exec app php artisan config:cache route:cache view:cache
```

## Rebuilding for upstream updates

The base tag `php8.4` floats with upstream FrankenPHP/PHP 8.4 patch releases. To pick up security fixes, re-run the workflow via **workflow_dispatch** (publishes `php8.4-dev`) or cut a new `vX.Y.Z` tag. The smoke test gates every publish — a broken upstream build can never reach GHCR.

---

# universal-backup

`ghcr.io/mhraymondwong/universal-backup:pg17` — a shared, generic backup image for every app on this stack: scheduled PostgreSQL dumps + filesystem archives + retention + optional S3-compatible offsite sync. Multi-arch (`linux/amd64`, `linux/arm64`), infra-only — no app code, no secrets baked in.

The `pg<N>` tag encodes the bundled `pg_dump` major version; it must be **≥ your Postgres server major** (e.g. `pg17` backs up Postgres ≤ 17).

On each scheduled run the container:

1. Dumps the database to `/backups/db-<timestamp>.sql.gz` (plain SQL, gzipped — restore with `gunzip | psql`)
2. Archives each path in `BACKUP_PATHS` to `/backups/<basename>-<timestamp>.tar.gz`
3. Deletes files older than `BACKUP_RETENTION_DAYS`
4. If `BACKUP_S3_BUCKET` is set, syncs `/backups` to the bucket

Every file is written as `<name>.tmp` first and renamed only on success — a half-written file is never mistaken for a good backup. A failed run exits non-zero; the next cron run still happens.

## For app developers

### Compose service

```yaml
backup:
  image: ghcr.io/mhraymondwong/universal-backup:pg17
  restart: unless-stopped
  environment:
    DB_HOST: postgres                  # compose service name of your Postgres
    DB_PORT: 5432
    DB_DATABASE: ${DB_DATABASE:-appdb}
    DB_USERNAME: ${DB_USERNAME:-appuser}
    DB_PASSWORD: ${DB_PASSWORD:?set DB_PASSWORD in .env}
    BACKUP_CRON: "${BACKUP_CRON:-0 3 * * *}"
    TZ: ${TZ:-UTC}
    BACKUP_PATHS: ${BACKUP_PATHS:-/app/storage}
    BACKUP_RETENTION_DAYS: ${BACKUP_RETENTION_DAYS:-14}
    BACKUP_S3_BUCKET: ${BACKUP_S3_BUCKET:-}
    BACKUP_S3_PREFIX: ${BACKUP_S3_PREFIX:-backups}
    BACKUP_S3_ENDPOINT: ${BACKUP_S3_ENDPOINT:-}
    BACKUP_S3_REGION: ${BACKUP_S3_REGION:-}
    BACKUP_S3_ACCESS_KEY: ${BACKUP_S3_ACCESS_KEY:-}
    BACKUP_S3_SECRET_KEY: ${BACKUP_S3_SECRET_KEY:-}
  volumes:
    - backups:/backups                 # writable — backup output lands here
    - ./app/storage:/app/storage:ro    # read-only; mount every path in BACKUP_PATHS this way
  depends_on:
    postgres: { condition: service_healthy }
    app: { condition: service_started }

volumes:
  backups:
```

### Environment variables

| Var | Default | Behaviour |
| --- | --- | --- |
| `DB_HOST` | `postgres` | Postgres host (compose service name) |
| `DB_PORT` | `5432` | Postgres port |
| `DB_DATABASE` | *(required)* | Database to dump — container fails fast if empty |
| `DB_USERNAME` | *(required)* | Dump user — fails fast if empty |
| `DB_PASSWORD` | *(required)* | Dump password — fails fast if empty |
| `BACKUP_CRON` | `0 3 * * *` | Cron schedule; written to the crontab at container start |
| `TZ` | `UTC` | Timezone for the schedule and file timestamps |
| `BACKUP_PATHS` | `/app/storage` | Space-separated absolute paths — one `<basename>-<TS>.tar.gz` each; missing paths are skipped with a warning; **empty string = database only** |
| `BACKUP_RETENTION_DAYS` | `14` | Local files older than N days are deleted each run |
| `BACKUP_RUN_ON_START` | `false` | `true` runs one backup at container start — if it fails the container exits non-zero (useful for smoke tests) |
| `BACKUP_S3_BUCKET` | empty | Set to enable offsite sync; empty = fully off |
| `BACKUP_S3_PREFIX` | `backups` | Key prefix inside the bucket |
| `BACKUP_S3_ENDPOINT` | empty | Custom S3 API endpoint (Backblaze B2, Cloudflare R2, MinIO) |
| `BACKUP_S3_REGION` | empty | Region for the endpoint |
| `BACKUP_S3_ACCESS_KEY` | empty | S3 access key |
| `BACKUP_S3_SECRET_KEY` | empty | S3 secret key |

### On-demand backup

```bash
docker compose exec backup backup.sh
```

### Restore

```bash
# Database — pipe a dump straight into Postgres
gunzip -c backups/db-<TS>.sql.gz | docker compose exec -T postgres psql -U appuser -d appdb

# Files — extract over the app directory (recreates storage/...)
tar -xzf backups/storage-<TS>.tar.gz -C ./app
```

## For client sysadmins — offsite (S3-compatible) backups

### Why offsite matters

A backup on the same disk dies with the server. Hardware failure, theft, fire, or ransomware takes the database *and* its backups together. Copying backups to a separate cloud bucket means the data survives the machine — this is the difference between an incident and a loss.

### Choosing a provider

Set the `BACKUP_S3_*` variables in the client's `.env` (same file as `DB_PASSWORD`). All S3-compatible providers work:

| Provider | `BACKUP_S3_ENDPOINT` | `BACKUP_S3_REGION` | How to get keys |
| --- | --- | --- | --- |
| AWS S3 | *(leave empty)* | e.g. `ap-southeast-1` | IAM → Users → *Security credentials* → Create access key |
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` | `<region>` part of the endpoint, e.g. `us-west-004` | B2 console → App Keys → create key restricted to the bucket (keyID → `ACCESS_KEY`, applicationKey → `SECRET_KEY`) |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` | `auto` | R2 → Manage API tokens → create token with *Object Read & Write* scoped to the bucket |
| MinIO (self-hosted) | `https://minio.example.com:9000` | empty (or `us-east-1`) | MinIO console → Access Keys → create a scoped service account |

Steps common to all: create a dedicated bucket (e.g. `acme-app-backups`), create credentials, set `BACKUP_S3_BUCKET`, `BACKUP_S3_ENDPOINT`, `BACKUP_S3_REGION` (per table), `BACKUP_S3_ACCESS_KEY`, `BACKUP_S3_SECRET_KEY`, optionally `BACKUP_S3_PREFIX`, then `docker compose up -d backup`.

**Least privilege:** the bucket holds sensitive data — give the key *write-only or scoped access to that one bucket* where the provider allows (B2 bucket-restricted keys, R2 bucket-scoped tokens, an IAM policy limited to `s3:PutObject`/`s3:ListBucket`/`s3:GetObject` on the backup bucket). Never reuse a root/admin key.

### Not using S3?

Leave every `BACKUP_S3_*` empty — the feature is fully off and backups stay local in the `backups` volume. To copy them off the machine:

```bash
docker compose cp backup:/backups ./backups-copy
```

### Changing the schedule

`BACKUP_CRON` is a standard 5-field cron expression evaluated in timezone `TZ`:

```yaml
environment:
  BACKUP_CRON: "0 3 * * *"        # 03:00 daily ...
  TZ: Asia/Hong_Kong              # ... in Hong Kong time
  # BACKUP_CRON: "0 */6 * * *"    # every 6 hours
  # BACKUP_CRON: "30 2 * * 0"     # 02:30 every Sunday
```

The schedule is applied when the container starts — `docker compose up -d backup` after editing `.env`.

### Restoring from S3

From any machine with the [AWS CLI](https://aws.amazon.com/cli/) (works with all S3-compatible providers via `--endpoint-url`):

```bash
# Everything back down:
aws s3 sync s3://<bucket>/backups ./backups \
  --endpoint-url <BACKUP_S3_ENDPOINT>   # omit for AWS S3

# Or a single dump:
aws s3 cp s3://<bucket>/backups/db-<TS>.sql.gz . --endpoint-url <endpoint>
```

Then follow the [Restore](#restore) steps above.

### Warning: back up `APP_KEY` too

Backups contain the database and files only — **not** the app's `.env`. Laravel encrypts some fields with `APP_KEY`; restoring data without the same `APP_KEY` leaves them permanently unreadable. Keep a copy of each client's `APP_KEY` in a password manager alongside this documentation.

## Backup image tags

| Tag | Produced by |
| --- | --- |
| `pg17` | Every publish (moving) |
| `pg17-vX.Y.Z` | Git tag `vX.Y.Z` (immutable) — tags are shared repo releases |
| `pg17-dev`, `sha-*` | Manual `workflow_dispatch` runs |

`latest` is never published — pin `pg17` or an immutable version tag. Breaking env-contract changes ship under a new major tag and a `CHANGELOG.md` entry, never silently.

### Publishing (maintainer guide)

`.github/workflows/build-publish-backup.yml` runs when `backup/**` or the workflow changes on `main` (publishes `pg17`), on `v*.*.*` tags (adds `pg17-vX.Y.Z`), and on manual dispatch (`pg17-dev`, `sha-*`). Every publish is gated by a smoke test against a real `postgres:17` service: a live dump, an archive, the healthcheck, and a forced-failure run.

**One-time after the first publish** — the `universal-backup` GHCR package starts private:

1. `https://github.com/mhraymondwong?tab=packages` → `universal-backup` → **Package settings → Danger Zone → Change visibility → Public**.
2. Same page → **Connect repository** → `universal-runtime` (renders this README on the package page).
3. Verify anonymous pull: `docker logout ghcr.io && docker pull ghcr.io/mhraymondwong/universal-backup:pg17`.
