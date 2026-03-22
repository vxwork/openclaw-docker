# syntax=docker/dockerfile:1.7-labs

# Stage 1: Builder（不變，已包含 ca-certificates + full deps）
FROM node:24-bookworm-slim AS builder

WORKDIR /build

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git && \
    npm install -g pnpm@latest && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/openclaw/openclaw.git . && \
    pnpm install --frozen-lockfile && \
    pnpm ui:build && \
    pnpm build

RUN mkdir -p /app/dist /app/node_modules /app/scripts /app/extensions && \
    cp -r dist/* /app/dist/ && \
    cp package.json pnpm-lock.yaml tsconfig.json tsdown.config.* /app/ && \
    cp -r node_modules /app/ && \
    cp -r scripts/* /app/scripts/ && \
    cp -r src /app/src/ && \
    cp -r extensions /app/extensions/ && \
    cp config.example.json openclaw.json.example /app/ 2>/dev/null || true

# Stage 2: Runtime - 使用完整 almalinux:10.1（有 dnf，穩定）
FROM almalinux:10.1

# 安裝必要包 + pnpm + jq
RUN dnf install -y epel-release && \
    dnf install -y --nodocs \
        curl ca-certificates jq nodejs npm python3 python3-pip \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts glibc-langpack-zh && \
    npm install -g pnpm@latest && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

RUN fc-cache -fv

# 设置 locale 避免警告
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh

COPY --from=builder /app /app
WORKDIR /app

# Python venv + 包
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        matplotlib \
        weasyprint \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

ENV PATH="/opt/venv/bin:/app/node_modules/.bin:/usr/local/bin:$PATH"

# 可選：保留 openclaw 用戶（root 運行）
#RUN useradd -m -s /bin/bash openclaw && \
#    chown -R openclaw:openclaw /app /opt/venv && \
#    mkdir -p /home/openclaw/.openclaw /home/openclaw/workspace && \
#    chown -R openclaw:openclaw /home/openclaw

COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
#CMD ["bash"]