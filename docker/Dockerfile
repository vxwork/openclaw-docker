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
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm /root/.bun

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
        openssl \
        jq \
        glibc-langpack-en && \
    dnf remove -y epel-release && \
    dnf clean all && \
    rm -rf /var/cache/dnf/* /var/log/dnf* /var/log/yum.* /tmp/* /var/tmp/*

# Install Node.js from Nodesource (version configurable via ARG)
RUN curl -fsSL https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x | bash - && \
    dnf install -y --setopt=install_weak_deps=False nodejs && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# Configure locale using glibc-langpack-en
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en

# Install Python packages for skills (only essential ones)
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge && \
    find /opt/venv -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
    find /opt/venv -type f -name "*.pyc" -delete 2>/dev/null || true && \
    find /opt/venv -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find /opt/venv -type d -name "test" -exec rm -rf {} + 2>/dev/null || true

WORKDIR /app

# Copy runtime essentials from builder (without node_modules)
# Note: Docker automatically optimizes multiple COPY instructions from the same 
# source stage into a single layer, so keeping them separate improves readability
# without increasing image size.
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
      @slack/web-api \
      @buape/carbon \
      grammy \
      zod \
      --prod && \
    # 3. 对 amazon-bedrock 插件目录单独安装（最可靠的兜底）
    echo "=== Installing amazon-bedrock plugin dependencies manually ===" && \
    cd /app/extensions/amazon-bedrock && \
    pnpm install --prod --no-frozen-lockfile || \
      echo "Warning: amazon-bedrock local install had issues, continuing..." && \
    cd /app && \
    # 4. 对 feishu 也再做一次（防止之前没完全生效）
    cd /app/extensions/feishu && \
    pnpm install --prod --no-frozen-lockfile || true && \
    cd /app && \
    # 5. 执行 postinstall（允许失败）
    node scripts/postinstall-bundled-plugins.mjs || \
      echo "Warning: postinstall-bundled-plugins.mjs failed (npm compatibility), continuing..." && \
    # 6. 删除不需要的大型包（llama-cpp 本地推理 + typescript 编译器）
    rm -rf \
      node_modules/.pnpm/@node-llama-cpp+linux-x64-cuda-ext@* \
      node_modules/.pnpm/@node-llama-cpp+linux-x64-cuda@* \
      node_modules/.pnpm/@node-llama-cpp+linux-x64-vulkan@* \
      node_modules/.pnpm/@node-llama-cpp+linux-x64@* \
      node_modules/.pnpm/node-llama-cpp@* \
      node_modules/.pnpm/koffi@* \
      node_modules/.pnpm/typescript@* && \
    # 清理 pnpm store 和缓存
    pnpm store prune && \
    rm -rf /root/.pnpm-store /root/.cache/pnpm /root/.npm /tmp/* && \
    # 删除 TypeScript 类型声明和 source maps
    find node_modules -type f \( \
      -name "*.d.ts" -o -name "*.d.mts" -o -name "*.d.cts" \
      -o -name "*.map" -o -name "*.js.map" \
      -o -name "*.ts" -o -name "*.tsx" \
      -o -name "*.md" \
    \) -delete 2>/dev/null || true && \
    # 删除文档、示例、测试、编辑器配置等非运行时目录
    find node_modules -type d \( \
      -name "test" -o -name "tests" -o -name "__tests__" \
      -o -name "example" -o -name "examples" \
      -o -name "docs" \
      -o -name ".github" -o -name ".vscode" \
    \) -exec rm -rf {} + 2>/dev/null || true && \
    # 删除非运行时文件
    find node_modules -type f \( \
      -name "LICENSE*" -o -name "LICENCE*" \
      -o -name "CHANGELOG*" -o -name "HISTORY*" -o -name "CHANGES*" \
      -o -name "AUTHORS*" -o -name "CONTRIBUTORS*" \
      -o -name ".npmignore" -o -name ".eslintrc*" -o -name ".prettierrc*" \
      -o -name ".editorconfig" -o -name ".jshintrc" \
      -o -name "tsconfig*.json" -o -name "jest.config*" \
      -o -name "Makefile" -o -name "Gruntfile*" -o -name "Gulpfile*" \
      -o -name "*.tsbuildinfo" \
    \) -delete 2>/dev/null || true && \
    chmod -R 755 /app && \
    ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

# Set proper permissions and create symlink (already done in RUN above)
# Setup Python virtual environment path
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]