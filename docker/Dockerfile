# ==================== Stage 2: Builder ====================
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

# Copy extension package.json files from ext-deps stage for dependency caching
COPY --from=ext-deps /out/ ./extensions/

# Install dependencies with cache optimization
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS="--max-old-space-size=2048" pnpm install --frozen-lockfile

# Copy full source code again (this will use cache if extensions didn't change)
RUN rm -rf extensions && git checkout extensions

# Build project
RUN pnpm build && \
    pnpm ui:build && \
    # Mark dist as fresh to avoid runtime recompilation
    touch -r dist/index.js dist/.fresh-marker 2>/dev/null || true

# Clean build artifacts but keep all dependencies for now
RUN find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete 2>/dev/null || true && \
    # Clean pnpm store and caches only (don't prune node_modules yet)
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm

# Prune production dependencies only and clean thoroughly
RUN CI=true pnpm prune --prod && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete 2>/dev/null || true && \
    # Remove unnecessary directories from node_modules
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "*.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.tsx" -delete 2>/dev/null || true && \
    # Clean pnpm store and caches
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm

# ==================== Stage 3: Runtime ====================
FROM almalinux:10.1 AS runtime

# Set timezone early
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Allow overriding Node.js version at build time (default to latest LTS)
ARG NODEJS_VERSION="24"

# Install minimal system dependencies in single layer
# Use dnf with aggressive cleanup for minimal footprint
RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
        epel-release && \
    dnf install -y --setopt=install_weak_deps=False --nodocs \
        curl \
        ca-certificates \
        python3 \
        python3-pip \
        procps-ng \
        hostname \
        openssl && \
    dnf clean all && \
    rm -rf /var/cache/dnf/* /var/log/dnf* /var/log/yum.*

# Install Node.js from Nodesource (version configurable via ARG)
RUN curl -fsSL https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x | bash - && \
    dnf install -y --setopt=install_weak_deps=False nodejs && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# Configure locale (minimal)
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en

# Install Python packages for skills (only essential ones)
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

WORKDIR /app

# Copy ONLY runtime essentials from builder (without node_modules)
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=builder /app/openclaw.mjs ./openclaw.mjs
# Copy only extensions directory (required for plugins)
COPY --from=builder /app/extensions ./extensions
# Skip docs to save space - uncomment if needed
COPY --from=builder /app/docs ./docs

# Install production dependencies only in runtime stage
RUN corepack enable pnpm && \
    pnpm install --frozen-lockfile --prod && \
    # Clean pnpm store after installation
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm && \
    # Remove markdown and TypeScript files from node_modules
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "*.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.tsx" -delete 2>/dev/null || true

# Set proper permissions
RUN chmod -R 755 /app

# Create openclaw CLI symlink
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

# Setup Python virtual environment path
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]