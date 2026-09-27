#!/bin/sh
# universal-backup — one backup run: Postgres dump + filesystem archives,
# retention pruning, optional S3-compatible offsite sync.
#
# Env contract (public API — see README; renames/removals need a major tag):
#   DB_HOST (postgres)  DB_PORT (5432)
#   DB_DATABASE  DB_USERNAME  DB_PASSWORD      (required, non-empty)
#   BACKUP_PATHS           (/app/storage; space-separated; empty = DB only)
#   BACKUP_RETENTION_DAYS  (14)
#   BACKUP_S3_BUCKET/PREFIX/ENDPOINT/REGION/ACCESS_KEY/SECRET_KEY (optional)
set -eu
set -o pipefail

DEST="/backups"
TS="$(date +%Y%m%d-%H%M%S)"

log()  { echo "[backup] $(date '+%Y-%m-%d %H:%M:%S %Z') $*"; }
warn() { log "WARN: $*" >&2; }
fail() { log "ERROR: $*" >&2; exit 1; }

: "${DB_DATABASE:?DB_DATABASE must be set}"
: "${DB_USERNAME:?DB_USERNAME must be set}"
: "${DB_PASSWORD:?DB_PASSWORD must be set}"
DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"
# No colon: a deliberately-empty BACKUP_PATHS means "database only".
BACKUP_PATHS="${BACKUP_PATHS-/app/storage}"

mkdir -p "$DEST"

# --- Database dump (plain SQL, gzipped — restore via `gunzip | psql`) ---
DUMP_TMP="$DEST/db-$TS.sql.gz.tmp"
log "dumping database ${DB_DATABASE}@${DB_HOST}:${DB_PORT}"
if ! PGPASSWORD="$DB_PASSWORD" pg_dump \
      -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_DATABASE" \
    | gzip > "$DUMP_TMP"; then
    rm -f "$DUMP_TMP"
    fail "pg_dump failed — backup aborted"
fi
mv "$DUMP_TMP" "$DEST/db-$TS.sql.gz"
log "wrote db-$TS.sql.gz"

# --- Filesystem archives: one <basename>-<TS>.tar.gz per path ---
# shellcheck disable=SC2086  # word-splitting of BACKUP_PATHS is intentional
for path in $BACKUP_PATHS; do
    if [ ! -e "$path" ]; then
        warn "$path does not exist — skipping"
        continue
    fi
    name="$(basename "$path")"
    parent="$(dirname "$path")"
    ARCH_TMP="$DEST/$name-$TS.tar.gz.tmp"
    if ! tar -czf "$ARCH_TMP" -C "$parent" "$name"; then
        rm -f "$ARCH_TMP"
        fail "archiving $path failed — backup aborted"
    fi
    mv "$ARCH_TMP" "$DEST/$name-$TS.tar.gz"
    log "wrote $name-$TS.tar.gz"
done

# --- Retention ---
log "pruning files older than ${RETENTION} days"
find "$DEST" -type f -mtime "+${RETENTION}" -delete

# --- Optional offsite sync to an S3-compatible target ---
if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
    log "syncing to s3://${BACKUP_S3_BUCKET}/${BACKUP_S3_PREFIX:-backups}"
    AWS_ACCESS_KEY_ID="${BACKUP_S3_ACCESS_KEY:-}" \
    AWS_SECRET_ACCESS_KEY="${BACKUP_S3_SECRET_KEY:-}" \
    aws s3 sync "$DEST" "s3://${BACKUP_S3_BUCKET}/${BACKUP_S3_PREFIX:-backups}" \
        ${BACKUP_S3_ENDPOINT:+--endpoint-url "$BACKUP_S3_ENDPOINT"} \
        ${BACKUP_S3_REGION:+--region "$BACKUP_S3_REGION"}
fi

log "done"
