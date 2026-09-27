# Changelog

All notable changes to the published images are documented here, per image
tag. Both images share `v*.*.*` git tags; each entry states which image it
describes.

## [pg17-v1.1.0] — universal-backup — 2026-09-27

Initial release of `ghcr.io/mhraymondwong/universal-backup:pg17`.

- Alpine 3.22 + `postgresql17-client`, busybox `crond`, `aws-cli`, `tzdata`.
- Scheduled Postgres dump (`db-<TS>.sql.gz`) + filesystem archives
  (`<basename>-<TS>.tar.gz`) + retention pruning + optional S3 offsite sync.
- Env contract (public API):

  | Var | Default |
  |---|---|
  | `DB_HOST` / `DB_PORT` | `postgres` / `5432` |
  | `DB_DATABASE` / `DB_USERNAME` / `DB_PASSWORD` | required |
  | `BACKUP_CRON` | `0 3 * * *` |
  | `TZ` | `UTC` |
  | `BACKUP_PATHS` | `/app/storage` |
  | `BACKUP_RETENTION_DAYS` | `14` |
  | `BACKUP_RUN_ON_START` | `false` |
  | `BACKUP_S3_BUCKET` / `PREFIX` / `ENDPOINT` / `REGION` / `ACCESS_KEY` / `SECRET_KEY` | unset |

## [php8.4-v1.0.0] — universal-runtime — 2026-09-25

Initial release of `ghcr.io/mhraymondwong/universal-runtime:php8.4`.

- FrankenPHP/Caddy on PHP 8.4, extensions `pdo_pgsql pgsql intl gd zip pcntl
  bcmath opcache redis`, Composer bundled, multi-arch amd64+arm64.
