# syntax=docker/dockerfile:1.7

# ==================== Stage 1: Builder ====================
FROM node:24-bookworm-slim AS builder

ARG OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
ARG OPENCLAW_BRANCH="main"

# Install base dependencies including git, curl, unzip
# Must install ca-certificates first for HTTPS operations
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Bun for build process (with retry logic)
RUN set -eux; \
    for attempt in 1 2 3 4 5; do \
      if curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL https://bun.sh/install | bash; then \
        break; \
      fi; \
      if [ "$attempt" -eq 5 ]; then \
        exit 1; \
      fi; \
      sleep $((attempt * 2)); \
    done
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable pnpm

WORKDIR /app

# Clone OpenClaw repository (shallow clone)
RUN git clone --depth=1 --branch=${OPENCLAW_BRANCH} ${OPENCLAW_REPO} .

# Install all dependencies with pnpm store cache
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS="--max-old-space-size=2048" pnpm install --frozen-lockfile

# Pre-add runtime deps required by bundled extensions (not declared in main lockfile).
# Done here so the runtime stage can use --frozen-lockfile cleanly without extra pnpm add steps.
# Note: postinstall-bundled-plugins.mjs is intentionally NOT run here — it auto-skips source
# checkouts (detects .git + src + extensions), so calling it in builder is a no-op.
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    pnpm add --workspace-root \
      @larksuiteoapi/node-sdk \
      https-proxy-agent \
      @aws-sdk/client-bedrock \
      @aws-sdk/client-sts \
      @aws-sdk/credential-providers \
      @sinclair/typebox \
      zod

# canvas:a2ui:bundle must run before build:docker — build:docker skips bundling but still
# copies the generated assets via canvas-a2ui-copy.ts, so the assets must exist first.
RUN pnpm canvas:a2ui:bundle && pnpm build:docker && pnpm ui:build

# Prune to production deps, strip native modules, and clean up in single layer
RUN pnpm prune --prod && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.md" -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.ts" -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.tsx" -delete 2>/dev/null || true && \
    find node_modules extensions -name "CHANGELOG*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "LICENSE*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "AUTHORS*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "README*" -delete 2>/dev/null || true && \
    find node_modules -name "*.node" -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm

# ==================== Stage 2: Python venv builder ====================
# Build Python venv on the same base as runtime to ensure binary compatibility.
# Kept as a separate stage so that pip/setuptools (~20MB) never enter the final image.
FROM almalinux:10.1 AS python-builder

RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
        python3 \
        python3-pip && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

# ==================== Stage 3: Runtime ====================
FROM almalinux:10.1 AS runtime

# Set timezone early
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Allow overriding Node.js version at build time (default to latest LTS)
ARG NODEJS_VERSION="24"

# Install minimal system dependencies.
# python3-pip is intentionally omitted — the venv is built in the python-builder stage
# and copied in, so pip is never needed here.
RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
        epel-release && \
    dnf install -y --setopt=install_weak_deps=False --nodocs \
        curl \
        ca-certificates \
        python3 \
        procps-ng \
        hostname \
        openssl \
        glibc-langpack-en && \
    dnf clean all && \
    rm -rf /var/cache/dnf/* /var/log/dnf* /var/log/yum.*

# Install Node.js from Nodesource (version configurable via ARG)
RUN curl -fsSL https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x | bash - && \
    dnf install -y --setopt=install_weak_deps=False nodejs && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# Configure locale using glibc-langpack-en
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en

# Copy pre-built Python venv from python-builder (pip/setuptools stay out of this image)
COPY --from=python-builder /opt/venv /opt/venv

WORKDIR /app

# Copy runtime essentials from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=builder /app/openclaw.mjs ./openclaw.mjs
COPY --from=builder /app/extensions ./extensions
COPY --from=builder /app/scripts ./scripts
# Copy docs/reference/templates (required for workspace setup)
COPY --from=builder /app/docs/reference/templates ./docs/reference/templates

# Install production dependencies and run postinstall for bundled plugin deps.
# Notes:
# - pnpm-workspace.yaml is not present here (not copied), so pnpm treats this as a
#   single-package install and resolves root deps only. Extension workspace deps
#   (@buape/carbon etc.) are handled by postinstall-bundled-plugins.mjs below.
# - --frozen-lockfile is intentionally omitted: the lockfile was built in a full workspace
#   context (with ui/ and packages/*) that doesn't exist in this runtime image, so frozen
#   mode would fail. pnpm still uses the lockfile for version pinning.
# - postinstall-bundled-plugins.mjs is wrapped in its own subshell so that its optional
#   failure does NOT silently mask failures in the pnpm install step above it.
RUN corepack enable pnpm && \
    pnpm install --prod && \
    (node scripts/postinstall-bundled-plugins.mjs || \
      echo "Warning: postinstall-bundled-plugins.mjs failed, continuing...") && \
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm && \
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "*.tsx" -delete 2>/dev/null || true && \
    find node_modules -name "CHANGELOG*" -delete 2>/dev/null || true && \
    find node_modules -name "LICENSE*" -delete 2>/dev/null || true && \
    find node_modules -name "AUTHORS*" -delete 2>/dev/null || true && \
    find node_modules -name "README*" -delete 2>/dev/null || true && \
    find node_modules -name "*.node" -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    chmod -R 755 /app && \
    ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

# Setup Python virtual environment path
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
