# universal-runtime

Multi-architecture Docker base runtime for **Laravel 13 + Filament 5** applications, powered by **FrankenPHP / Caddy on PHP 8.4**, published to GitHub Container Registry (GHCR).

This image contains **infrastructure only** — no application code, no `.env` secrets, no Node.js, no database server. Consumer apps mount their code at `/app`; the built-in Caddyfile serves `/app/public` automatically.

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
git remote add origin git@github.com:<your-user>/universal-runtime.git
git push -u origin main
```

Or create the repo at github.com first, then push.

### 2. Release a version

```bash
git tag v1.0.0
git push --tags
```

The workflow `.github/workflows/build-publish.yml` builds both architectures, smoke-tests the image (PHP version, all extensions, Composer), then pushes to GHCR. A manual run is also available under **Actions → Build & Publish Runtime Image → Run workflow**.

### 3. Make the package public (one-time)

The first publish creates the package as private. To make it public:

1. Go to `https://github.com/<your-user>?tab=packages` → select `universal-runtime`.
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public**.
3. Also under **Package settings → Connect repository**, link this repo so the README renders on the package page.

Customers can then pull without authentication:

```bash
docker pull ghcr.io/<your-user>/universal-runtime:php8.4
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
    image: ghcr.io/<your-user>/universal-runtime:php8.4
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
