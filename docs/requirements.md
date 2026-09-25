# Requirements: Universal App Runtime Base Image

## 1. Project Goal

Build and maintain an automated repository that compiles, tests, and publishes a public, multi-architecture Docker base runtime image to GitHub Container Registry (GHCR).

This image will serve as the standardized execution environment for multiple Laravel + Filament projects powered by FrankenPHP and Caddy, connecting to external PostgreSQL databases.

---

## 2. Architecture & Design Principles

- **Decoupled Architecture**: This image contains **strictly infrastructure and runtime dependencies**. It must **never** contain application business logic, Laravel application code, `.env` secrets, or client credentials.
- **No In-Container Database**: PostgreSQL will run in its own official container (`postgres:16-alpine`); do not install PostgreSQL server daemons in this image.
- **No Node.js / NPM**: Frontend asset building occurs during the build/release stage, not in production runtime. Keep the image lightweight and attack-surface minimal.
- **Multi-Architecture**: Must target both `linux/amd64` (Intel/AMD client machines/servers) and `linux/arm64` (Apple Silicon development environments).

---

## 3. Container Specifications

### 3.1 Upstream Base

Use the official FrankenPHP Docker base tracking the latest stable PHP 8.4 build:

```dockerfile
FROM dunglas/frankenphp:php8.4
```

### 3.2 Required PHP Extensions

Install the following extensions using the built-in `install-php-extensions` script:

| Category                    | Extensions                     |
| --------------------------- | ------------------------------ |
| Database                    | `pdo_pgsql`, `pgsql`           |
| Filament & UI               | `intl`, `gd`, `zip`            |
| Performance & Concurrency   | `pcntl`, `bcmath`, `opcache`   |
| Caching & Queues            | `redis`                        |

### 3.3 Composer

Include the latest stable Composer binary (copied from the official `composer` image) at `/usr/bin/composer` for consumer dependency workflows.

### 3.4 Container Working Directory

```dockerfile
WORKDIR /app
```

---

## 4. GitHub Actions CI/CD Pipeline

Implement `.github/workflows/build-publish.yml` with the following workflow:

### 4.1 Trigger Conditions

- Push of semantic version tags (e.g., `v*.*.*`)
- Manual trigger via `workflow_dispatch`

### 4.2 Build Steps

1. **Repository Checkout**: Check out code using `actions/checkout@v4`.
2. **QEMU Setup**: Set up QEMU for multi-architecture emulation using `docker/setup-qemu-action@v3`.
3. **Buildx Setup**: Configure Docker Buildx using `docker/setup-buildx-action@v3`.
4. **Registry Authentication**: Log in to GHCR using `docker/login-action@v3` with repository secrets:
   - Registry: `ghcr.io`
   - Username: `${{ github.actor }}`
   - Password: `${{ secrets.GITHUB_TOKEN }}`
5. **Smoke Test**: Build for the runner's native platform (`linux/amd64`) and verify before pushing — PHP 8.4 present, FrankenPHP present, Composer runs, and every required extension loads (`php -m`). The job must fail before publishing if any check fails.
6. **Build and Push**:
   - Platforms: `linux/amd64`, `linux/arm64`
   - Cache: Use GitHub Actions cache (`type=gha`) for fast incremental builds.
   - Tags:
     - `ghcr.io/${{ github.repository_owner }}/universal-runtime:php8.4`
     - `ghcr.io/${{ github.repository_owner }}/universal-runtime:latest`
     - Pinned version tag (e.g., `ghcr.io/${{ github.repository_owner }}/universal-runtime:php8.4-v1.0.0`)

---

## 5. Deliverables Expected from AI Agent

- `Dockerfile` — Clean, commented definition reflecting the requirements above.
- `.dockerignore` — Exclude unnecessary repository files (`.git`, `README.md`, `.github`).
- `.github/workflows/build-publish.yml` — Fully functional multi-arch CI/CD build script.
- `README.md`:
  - Short description of the image.
  - Instructions on how to set the package visibility to Public in GHCR.
  - Example snippet showing how consumer applications should mount `./app` into `/app` using `docker-compose.yml`.
