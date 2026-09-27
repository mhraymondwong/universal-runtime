# Universal Backup — scheduled PostgreSQL + filesystem backups.
# Shared, generic backup image for universal-runtime app stacks.
# Infrastructure only: no application code, no secrets, no app-specific logic.
FROM alpine:3.22

# Postgres client major version. Bump + retag for a new pg<N> image line
# (e.g. PG_MAJOR=18 once postgresql18-client lands in a stable Alpine).
ARG PG_MAJOR=17

LABEL org.opencontainers.image.source="https://github.com/mhraymondwong/universal-runtime" \
      org.opencontainers.image.description="Scheduled PostgreSQL + file backup image for universal-runtime app stacks" \
      org.opencontainers.image.licenses="MIT"

# busybox crond (already in alpine) is used instead of dcron — dcron's
# crond calls setpgid() unconditionally and fails as PID 1 in containers.
# tzdata enables TZ= for local-time scheduling of BACKUP_CRON.
RUN apk add --no-cache postgresql${PG_MAJOR}-client tar gzip aws-cli tzdata

COPY backup.sh entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

# Entrypoint writes /etc/crontabs/root from BACKUP_CRON (default 03:00),
# optionally runs one backup (BACKUP_RUN_ON_START), then execs crond.
HEALTHCHECK --interval=60s --timeout=5s --retries=5 --start-period=30s \
    CMD grep -aq crond /proc/1/cmdline || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
