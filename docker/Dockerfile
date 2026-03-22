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
    pnpm build && \
    # 标记 dist 为最新状态，避免运行时重新编译
    touch -r dist/index.js dist/.fresh-marker 2>/dev/null || true

# 准备运行时环境 - 复制完整的项目目录
RUN mkdir -p /app && \
    cp -r . /app/ && \
    # 设置工作目录权限
    chmod -R 755 /app

# ==================== Stage 2: Runtime ====================
FROM almalinux:10.1

# 安装系统依赖
RUN dnf install -y epel-release && \
    dnf install -y --nodocs \
        curl ca-certificates jq python3 python3-pip \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts glibc-langpack-zh && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# 安装 Node.js 24（与 builder 阶段保持一致）
RUN curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    dnf install -y nodejs && \
    npm install -g pnpm@latest && \
    dnf clean all

# 配置字体缓存和 locale
RUN fc-cache -fv

ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh

# 复制应用
COPY --from=builder /app /app
WORKDIR /app

# 创建 openclaw 命令的软链接（避免重复安装，节省空间）
RUN ln -s /app/node_modules/.bin/openclaw /usr/local/bin/openclaw || \
    # 如果没有预编译的 bin，则从源码安装
    npm install -g .

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