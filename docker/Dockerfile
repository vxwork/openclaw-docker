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

# 安裝 Node.js + 最小系統依賴
RUN microdnf install -y curl ca-certificates && \
    curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    microdnf install -y nodejs && \
    microdnf install -y \
        python3 \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts && \
    microdnf clean all && \
    rm -rf /var/cache/microdnf/*

RUN fc-cache -fv

COPY --from=builder /app /app
WORKDIR /app

# 全局安裝 openclaw CLI
RUN npm install -g /app && \
    ln -sf $(which openclaw) /usr/bin/openclaw 2>/dev/null || true

# Python venv + 必要包
RUN python3 -m venv /opt/venv --without-pip && \
    curl -sSL https://bootstrap.pypa.io/get-pip.py | /opt/venv/bin/python3 && \
    /opt/venv/bin/pip install --no-cache-dir \
        matplotlib \
        weasyprint \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

ENV PATH="/opt/venv/bin:/app/node_modules/.bin:$PATH"

# 註解掉 openclaw 用戶建立（目前使用 root）
# RUN useradd -m -s /bin/bash openclaw && \
#     chown -R openclaw:openclaw /app /opt/venv && \
#     mkdir -p /home/openclaw/.openclaw /home/openclaw/workspace && \
#     chown -R openclaw:openclaw /home/openclaw

# ==== entrypoint 部分 ====
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 明確指定以 root 運行（可省略，因為預設就是 root）
# USER root

WORKDIR /app

# 沒有暴露端口
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 如果 entrypoint.sh 最後會 exec 某個命令，這裡的 CMD 可以留空或作為預設參數
# CMD ["bash"]   ← 建議先註解掉，除非你確定 entrypoint 會使用 "$@"