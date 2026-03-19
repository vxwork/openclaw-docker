## openclaw-docker

This repository provides a Docker image build for OpenClaw. The image can be built locally or via GitHub Actions and pushed to GitHub Container Registry (GHCR).

**Features**

- Automated build via GitHub Actions (workflow_dispatch)
- Push to GHCR after successful build
- Build cache support to speed up subsequent builds

## How to build (GitHub Actions)

1. Open the repository's **Actions** tab on GitHub.
2. Select the `Build OpenClaw Docker Image` workflow.
3. Click **Run workflow**, choose the branch and start the job.

The workflow is manually triggered (`workflow_dispatch`) and uses the `docker/Dockerfile` in this repository.

## Image info

- Registry: `ghcr.io`
- Image name: `vxwork/openclaw-docker/online-base`
- Tag example: `linux_latest`

Pull example:

```bash
docker pull ghcr.io/vxwork/openclaw-docker/online-base:linux_latest
```

## Run locally

Run with `docker run` (example):

```bash
docker run -d --name openclaw -p 18789:18789 \
  -v openclaw-config:/app/config -v openclaw-data:/app/data \
  ghcr.io/vxwork/openclaw-docker/online-base:linux_latest
```

Or use `docker-compose` (recommended when using this repository's compose file).
This repo includes `docker-compose.yml` that defines a service named `openclawbot`.
By default the compose file mounts `./config` to `/root/.openclaw` inside the container
so the entrypoint can persist configuration and pairing tokens there.

```bash
# start in detached mode
docker compose up -d

# stop and remove
docker compose down
```

If you prefer to build locally before running with `docker run`:

```bash
docker build -t openclaw:local -f docker/Dockerfile .
docker run -d --name openclaw -p 18789:18789 openclaw:local
```

## First-run configuration

This image includes an entrypoint script that initializes configuration on first start.

- The compose file mounts `./config` to `/root/.openclaw` inside the container. On first start,
  the entrypoint checks for `/root/.openclaw/openclaw.json`. If missing it:
  - creates `/root/.openclaw/workspace` and `/root/.openclaw/pairing`
  - generates a device token and writes `/root/.openclaw/pairing/device.json`
  - starts the gateway with `--allow-unconfigured` so you can complete initial setup

- To manually run the config helper inside a running container (if needed):

```bash
# for docker run example
docker exec -it openclaw openclaw config

# for docker compose example (service name: openclawbot)
docker compose exec openclawbot openclaw config
```

（也可使用 `pnpm openclaw config`，镜像中已把 `openclaw` 加入 PATH。）

Make sure the host `./config` directory is writable by the container, so configuration
persists across restarts.

## Notes on Dockerfile

- The `docker/Dockerfile` in this repository is based on `almalinux:10.1-minimal` and installs Node.js via NodeSource. It then installs `pnpm`, clones the `openclaw` repository, installs dependencies and builds the project.
- The image exposes port `18789` and defines `VOLUME` entries for persistent `config` and `data`.

## Migration from `qverisbot-docker`

This repository has been updated to follow the layout and conventions from the `qverisbot-docker` main branch. The Dockerfile uses `almalinux` for packaging as requested; if you want an exact 1:1 copy of that repo's files, provide the repo or point to specific diffs and I will sync them precisely.

## Recommendation: Qveris AI for OpenClaw

For an enhanced OpenClaw experience, consider using Qveris AI — a toolset that integrates with OpenClaw and provides automation and AI-driven helpers. Qveris AI is recommended as a companion for OpenClaw deployments.

## Troubleshooting

- If the service does not start, inspect container logs:

```bash
# view logs for docker run example
docker logs -f openclaw

# view logs for docker compose example (service name: openclawbot)
docker compose logs -f openclawbot
```

- Interactive shell:

```bash
docker exec -it openclaw /bin/sh       # docker run example
docker compose exec openclawbot /bin/sh # compose example
```

### Common Issues

#### 1. Plugin Configuration Error: "extension entry escapes package directory"

If you encounter this error during startup:
```
Failed to start CLI: Error: Config validation failed: plugins: plugin: extension entry escapes package directory: ./index.js
```

**Solution**: The Docker image includes a patch (`openclaw-discovery-entry-not-found.patch`) that fixes this issue. Make sure you're using the latest image version.

#### 2. First-run Configuration Wizard

By default, the container will prompt for configuration on first start. To skip the configuration wizard:

**Using docker-compose:**
```yaml
environment:
  - OPENCLAW_SKIP_CONFIG=true
```

**Using docker run:**
```bash
docker run -e OPENCLAW_SKIP_CONFIG=true ...
```

#### 3. Git Clone Failures

If the build fails with git clone errors:
- For public repositories: Check network connectivity
- For private repositories: Use `--build-arg GITHUB_TOKEN=<your_token>` when building
