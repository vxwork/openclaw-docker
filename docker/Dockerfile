# syntax=docker/dockerfile:1.7-labs

# Stage 1: Builder
FROM node:24-bookworm-slim AS builder

WORKDIR /build

# Install ca-certificates + git + pnpm in one layer
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git && \
    npm install -g pnpm@latest && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Clone + install FULL dependencies (NO --prod) + build
RUN git clone --depth=1 https://github.com/openclaw/openclaw.git . && \
    pnpm install --frozen-lockfile && \
    pnpm ui:build && \
    pnpm build

# After build, copy ONLY what runtime actually needs
# (dist/ + minimal node_modules + configs)
# This keeps the final image small despite installing dev deps temporarily
RUN mkdir -p /app/dist /app/node_modules && \
    cp -r dist/* /app/dist/ && \
    cp package.json pnpm-lock.yaml /app/ && \
    # Only copy production node_modules if possible, but for CLI reliability copy full
    cp -r node_modules /app/ && \
    cp config.example.json openclaw.json.example /app/ 2>/dev/null || true

# Stage 2: Runtime - almalinux:10.1-minimal
FROM almalinux:10.1-minimal

# 安裝 Node.js + pnpm + jq（entrypoint 需要 jq）
RUN microdnf install -y curl ca-certificates jq && \
    curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    microdnf install -y nodejs && \
    npm install -g pnpm@latest && \                    # ← 這裡安裝全局 pnpm
    microdnf install -y \
        python3 \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts && \
    microdnf clean all && \
    rm -rf /var/cache/microdnf/*

# ... fc-cache -fv 保持不變 ...

COPY --from=builder /app /app
WORKDIR /app

# 為了讓 pnpm openclaw 能工作，複製更多必要的檔案（尤其是 pnpm-lock.yaml 和 .pnpm 結構）
# 如果 builder 階段有 pnpm store，也可以 COPY --from=builder /root/.local/share/pnpm /root/.local/share/pnpm
# 但為了簡單，這裡假設用全局 pnpm + 專案內的 lockfile

# Python venv 部分保持不變...

ENV PATH="/opt/venv/bin:/app/node_modules/.bin:/usr/local/bin:$PATH"   

# ... useradd 註解部分保持 ...

COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]