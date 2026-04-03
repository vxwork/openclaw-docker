# syntax=docker/dockerfile:1.7

# ==================== Stage 1: Extension Dependencies ====================
# Extract only package.json files from extensions for better cache utilization
FROM node:24-bookworm-slim AS ext-deps

ARG OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
ARG OPENCLAW_BRANCH="main"

WORKDIR /tmp/openclaw

# Install git and clone repository (shallow clone for speed)
# Must install ca-certificates first for HTTPS to work
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth=1 --branch=${OPENCLAW_BRANCH} ${OPENCLAW_REPO} .

WORKDIR /tmp/extensions

# Copy extensions from cloned repository
RUN cp -r /tmp/openclaw/extensions/. .

RUN mkdir -p /out && \
    for dir in */; do \
      if [ -f "$dir/package.json" ]; then \
        ext_name=$(basename "$dir"); \
        mkdir -p "/out/$ext_name" && \
        cp "$dir/package.json" "/out/$ext_name/package.json"; \
      fi; \
    done

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

# Build project, prune dependencies, and clean in single layer
RUN pnpm build && \
    pnpm ui:build && \
    pnpm add @larksuiteoapi/node-sdk https-proxy-agent --workspace-root && \
    node scripts/postinstall-bundled-plugins.mjs || true && \
    touch -r dist/index.js dist/.fresh-marker 2>/dev/null || true && \
    CI=true pnpm prune --prod && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.md" -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.ts" -delete 2>/dev/null || true && \
    find node_modules extensions -name "*.tsx" -delete 2>/dev/null || true && \
    find node_modules extensions -name "CHANGELOG*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "LICENSE*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "AUTHORS*" -delete 2>/dev/null || true && \
    find node_modules extensions -name "README*" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.mts" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.cts" -delete 2>/dev/null || true && \
    find node_modules -name "*.map" -delete 2>/dev/null || true && \
    find node_modules -type d \( -name "__tests__" -o -name "test" -o -name "tests" -o -name "spec" \) \
        -prune -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules \( -name "*.spec.js" -o -name "*.test.js" -o -name "*.spec.mjs" -o -name "*.test.mjs" \) \
        -delete 2>/dev/null || true && \
    find node_modules -name "*.node" -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm

# ==================== Stage 3: Python venv builder ====================
# Build Python venv on the same base as runtime to ensure binary compatibility.
# Kept as a separate stage so pip/setuptools never enter the final image.
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

# ==================== Stage 4: Runtime ====================
FROM almalinux:10.1 AS runtime

# Set timezone early
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Allow overriding Node.js version at build time (default to latest LTS)
ARG NODEJS_VERSION="24"

# Install minimal system dependencies in single layer
# python3-pip intentionally omitted — venv is built in python-builder stage
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

# Install production dependencies, clean up, set permissions, and create symlink in single layer
RUN corepack enable pnpm && \
    # 1. 基础生产依赖安装
    pnpm install --frozen-lockfile --prod && \
    # 2. 强制添加所有常见 bundled plugins 的缺失依赖（一次性解决 feishu + amazon-bedrock + 其他）
    pnpm add \
      @larksuiteoapi/node-sdk \
      https-proxy-agent \
      @aws-sdk/client-bedrock \
      @aws-sdk/client-sts \
      @aws-sdk/credential-providers \
      @sinclair/typebox \
      zod \
      --prod && \
    # 3. 执行 postinstall（允许失败）
    (node scripts/postinstall-bundled-plugins.mjs || \
      echo "Warning: postinstall-bundled-plugins.mjs failed, continuing...") && \
    # 4. 重建 native 模块
    pnpm rebuild --recursive || true && \
    # 5. 清理
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm && \
    find node_modules -name "*.md" -delete 2>/dev/null || true && \
    find node_modules -name "*.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.tsx" -delete 2>/dev/null || true && \
    find node_modules -name "CHANGELOG*" -delete 2>/dev/null || true && \
    find node_modules -name "LICENSE*" -delete 2>/dev/null || true && \
    find node_modules -name "AUTHORS*" -delete 2>/dev/null || true && \
    find node_modules -name "README*" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.ts" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.mts" -delete 2>/dev/null || true && \
    find node_modules -name "*.d.cts" -delete 2>/dev/null || true && \
    find node_modules -name "*.map" -delete 2>/dev/null || true && \
    find node_modules -type d \( -name "__tests__" -o -name "test" -o -name "tests" -o -name "spec" \) \
        -prune -exec rm -rf {} + 2>/dev/null || true && \
    find node_modules \( -name "*.spec.js" -o -name "*.test.js" -o -name "*.spec.mjs" -o -name "*.test.mjs" \) \
        -delete 2>/dev/null || true && \
    find node_modules \( -name "*.flow" -o -name "*.coffee" -o -name "*.gyp" -o -name "*.gypi" \) \
        -delete 2>/dev/null || true && \
    find node_modules -name "*.node" -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    chmod -R 755 /app && \
    ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

# Setup Python virtual environment path
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
