# Universal App Runtime — FrankenPHP + PHP 8.4
# Standardized execution environment for Laravel 13 + Filament 5 applications.
# Infrastructure only: no application code, no .env, no Node.js, no DB server.
FROM dunglas/frankenphp:php8.4

# Links the GHCR package page to this repository.
LABEL org.opencontainers.image.source="https://github.com/mhraymondwong/universal-runtime" \
      org.opencontainers.image.description="FrankenPHP PHP 8.4 runtime for Laravel 13 + Filament 5 apps"

# PHP extensions required by Laravel 13 + Filament 5 + PostgreSQL.
# install-php-extensions is bundled in the upstream image.
RUN install-php-extensions \
    # Database
    pdo_pgsql pgsql \
    # Filament & UI
    intl gd zip \
    # Performance & concurrency
    pcntl bcmath opcache \
    # Caching & queues
    redis

# Composer for dependency installs inside consumer builds/containers.
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Consumer applications mount or copy their code here. The upstream
# Caddyfile serves /app/public; SERVER_NAME controls HTTP vs auto-HTTPS.
WORKDIR /app
