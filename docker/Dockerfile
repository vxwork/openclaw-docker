# syntax=docker/dockerfile:1.7-labs

# ==================== Stage 1: Builder ====================
FROM node:24-bookworm-slim AS builder

WORKDIR /build

# 安装基础依赖
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git && \
    npm install -g pnpm@latest && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 克隆源码并构建
RUN git clone --depth=1 https://github.com/openclaw/openclaw.git . && \
    pnpm install --frozen-lockfile && \
    pnpm ui:build && \
    pnpm build

# 准备运行时环境（包含完整的源码和编译产物）
RUN mkdir -p /app && \
    cp -r dist package.json pnpm-lock.yaml node_modules src scripts extensions config.example.json openclaw.json.example /app/ && \
    # 复制构建配置文件（如果存在）
    (ls tsconfig.json tsdown.config.* 2>/dev/null && cp -t /app tsconfig.json tsdown.config.* 2>/dev/null) || true

# ==================== Stage 2: Runtime ====================
FROM almalinux:10.1

# 安装系统依赖和运行时环境
RUN dnf install -y epel-release && \
    dnf install -y --nodocs \
        curl ca-certificates jq nodejs npm python3 python3-pip \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts glibc-langpack-zh && \
    npm install -g pnpm@latest && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# 配置字体缓存和 locale
RUN fc-cache -fv

ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh

# 复制应用
COPY --from=builder /app /app
WORKDIR /app

# 配置 Python 虚拟环境和依赖包
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        matplotlib \
        weasyprint \
        reportlab \
        pillow && \
    /opt/venv/bin/pip cache purge

ENV PATH="/opt/venv/bin:/app/node_modules/.bin:/usr/local/bin:$PATH"

# 复制启动脚本
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]