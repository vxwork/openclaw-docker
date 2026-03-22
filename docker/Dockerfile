# syntax=docker/dockerfile:1.7-labs

# ==================== Stage 1: Extension Dependencies ====================
# Extract only package.json files from extensions to optimize cache layers
FROM node:24-bookworm-slim AS ext-deps
WORKDIR /extensions
COPY openclaw/extensions ./
RUN mkdir -p /out && \
    for dir in */; do \
      if [ -f "$dir/package.json" ]; then \
        mkdir -p "/out/$dir" && \
        cp "$dir/package.json" "/out/$dir/package.json"; \
      fi; \
    done

# ==================== Stage 2: Builder ====================
FROM node:24-bookworm-slim AS builder

WORKDIR /build

# Install Bun for build process
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

RUN corepack enable

# Install dependencies with cache optimization
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    git clone --depth=1 https://github.com/openclaw/openclaw.git . && \
    NODE_OPTIONS="--max-old-space-size=2048" pnpm install --frozen-lockfile

# Copy extension package.json files for proper dependency resolution
COPY --from=ext-deps /out/ ./extensions/

# Build project
RUN pnpm build && \
    pnpm ui:build && \
    # Mark dist as fresh to avoid runtime recompilation
    touch -r dist/index.js dist/.fresh-marker 2>/dev/null || true

# Prune dev dependencies and clean before copying to runtime
RUN CI=true pnpm prune --prod 2>/dev/null || true && \
    pnpm store prune 2>/dev/null || true

# Prepare runtime directory with all necessary files
RUN mkdir -p /app && \
    cp -r dist src package.json pnpm-lock.yaml openclaw.mjs scripts docs extensions /app/ && \
    # Copy config if it exists (optional)
    if [ -d "config" ]; then cp -r config /app/; fi && \
    chmod -R 755 /app && \
    rm -rf /build/*

# ==================== Stage 3: Runtime Base ====================
FROM almalinux:10.1

# Set timezone early
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install minimal system dependencies
RUN dnf install -y epel-release && \
    dnf install -y --nodocs \
        curl ca-certificates jq python3 python3-pip \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts glibc-langpack-zh procps-ng hostname openssl && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# Install Node.js 24 from Nodesource
RUN curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    dnf install -y nodejs && \
    dnf clean all

# Configure fonts and locale
RUN fc-cache -fv

ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh

WORKDIR /app

# Copy application from builder (includes pruned node_modules)
COPY --from=builder /app /app

# Create non-root user for security (matching OpenClaw official practice)
#RUN chown -R 1000:1000 /app

# Switch to non-root user
#USER 1000

# Expose default ports#
#EXPOSE 18789 18792

# Health check
#HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#    CMD curl -f http://localhost:18789/health || exit 1

# Create openclaw CLI symlink
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

# Configure Python virtual environment
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        matplotlib \
        weasyprint \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

ENV PATH="/opt/venv/bin:/app/node_modules/.bin:/usr/local/bin:$PATH"

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]