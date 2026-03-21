# syntax=docker/dockerfile:1.7-labs

# Stage 1: Builder
FROM node:24-bookworm-slim AS builder

WORKDIR /build

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends git && \
    npm install -g pnpm@latest && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/openclaw/openclaw.git . && \
    pnpm install --frozen-lockfile --prod && \
    pnpm ui:build && \
    pnpm build

# 只複製最小必要檔案
RUN mkdir -p /app/dist /app/node_modules && \
    cp -r dist/* /app/dist/ && \
    cp package.json pnpm-lock.yaml /app/ && \
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

# 建立非 root 使用者
#RUN useradd -m -s /bin/bash openclaw && \
#    chown -R openclaw:openclaw /app /opt/venv && \
#    mkdir -p /home/openclaw/.openclaw /home/openclaw/workspace && \
#    chown -R openclaw:openclaw /home/openclaw

# ==== 你要求的 entrypoint 部分 ====
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

#USER openclaw
WORKDIR /app

# 沒有暴露端口（符合你的要求）
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
#CMD ["bash"]