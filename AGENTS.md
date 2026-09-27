# Repository contracts

This repo publishes shared, infra-only base images. Every project on the
Laravel + Filament + PostgreSQL stack consumes them — changes here affect all
downstream apps and their deployed clients. Obey these contracts.

## Images

| Image | Dir | Registry | Contents |
|---|---|---|---|
| `universal-runtime` | repo root | `ghcr.io/mhraymondwong/universal-runtime` | FrankenPHP/Caddy/PHP 8.4 runtime. Infra only. |
| `universal-backup` | `backup/` | `ghcr.io/mhraymondwong/universal-backup` | Scheduled Postgres + file backups. Infra only. |

## Hard rules

- **Infra only.** No application code, no `.env`, no secrets, no Node.js, no
  database server in any image. Consumer apps mount code at `/app`; app state
  lives at `/app/storage`.
- **Genericness.** Never hard-code app names, database names, usernames, or
  consumer repo paths — grep for consumer identifiers must return nothing.
  Docs use `appdb` / `appuser` / `example.com` placeholders only.
- **Env vars are a public API.** Renaming or removing a published env var, or
  changing its meaning/defaults, is a breaking change: it requires a new
  major image tag AND a `CHANGELOG.md` entry. Adding new optional vars with
  defaults is safe.
- **Tags.** Backup image: `pg<N>` moving + `pg<N>-vX.Y.Z` immutable — never
  publish `latest` (in metadata-action steps this requires
  `flavor: latest=false`; the default `latest=auto` adds it on tag pushes).
  Runtime image: `php8.4`, `latest`, `php8.4-vX.Y.Z`.
  Releases share `v*.*.*` git tags (one tag releases both images).
- **Scheduling.** Busybox `crond` only — never `dcron` (its `setpgid()` call
  fails as PID 1 in containers). `BACKUP_CRON` + `TZ` drive the schedule.
- **No multi-database support** in the backup image yet; keep the single-DB
  `DB_*` contract stable so a future `BACKUP_DATABASES` can be added without
  breaking existing deployments.
- **Smoke tests gate every publish.** A broken build must never reach GHCR.
