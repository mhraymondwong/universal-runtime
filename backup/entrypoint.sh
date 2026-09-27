#!/bin/sh
# Container entrypoint: render the crontab from BACKUP_CRON, optionally run
# one backup now, then exec busybox crond as PID 1.
set -eu

CRON="${BACKUP_CRON:-0 3 * * *}"
TZ="${TZ:-UTC}"

mkdir -p /etc/crontabs
# Job output goes to PID 1's stdout/stderr so it appears in
# `docker logs` / `docker compose logs backup`.
printf '%s %s\n' "$CRON" \
    '/usr/local/bin/backup.sh >>/proc/1/fd/1 2>>/proc/1/fd/2' \
    > /etc/crontabs/root

echo "[entrypoint] schedule '$CRON' (TZ=$TZ)"

if [ "${BACKUP_RUN_ON_START:-false}" = "true" ]; then
    echo "[entrypoint] BACKUP_RUN_ON_START=true — running one backup now"
    # set -e propagates failure: the container exits non-zero.
    /usr/local/bin/backup.sh
fi

exec crond -f -l 2
