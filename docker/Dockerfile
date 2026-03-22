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
    touch -r dist/index.js dist/.fresh-marker 2>/dev/null || true && \
    # 清理 node_modules 中的开发工具，但保留 extensions 运行所需依赖
    pnpm prune --prod 2>/dev/null || true

# 只复制构建产物和必要文件（不包含 node_modules）
RUN mkdir -p /app && \
    # 复制编译后的产物、源码和完整的依赖
    # dist: 包含编译后的 JS 代码（包括 extensions 的编译结果）
    # src: TypeScript 源码（用于时间戳检查）
    # package.json + pnpm-lock.yaml: 依赖声明文件
    # openclaw.mjs: CLI 主入口
    # scripts: 启动脚本
    # docs: 文档模板（包含 AGENTS.md 等必需模板）
    # node_modules: 已安装的完整依赖（包含 extensions 所需依赖）
    cp -r dist src package.json pnpm-lock.yaml openclaw.mjs scripts docs node_modules /app/ && \
    # 如果 config 目录存在，则复制它
    if [ -d "config" ]; then cp -r config /app/; fi && \
    chmod -R 755 /app && \
    # 清理构建目录
    rm -rf /build/*

# ==================== Stage 2: Runtime ====================
FROM almalinux:10.1

# 设置时区为 UTC（与构建环境保持一致）
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装系统依赖（精简版）
RUN dnf install -y epel-release && \
    dnf install -y --nodocs \
        curl ca-certificates jq python3 python3-pip \
        cairo pango gdk-pixbuf2 libpng libjpeg-turbo freetype fontconfig harfbuzz \
        google-noto-sans-cjk-fonts glibc-langpack-zh && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# 安装 Node.js 24
RUN curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    dnf install -y nodejs && \
    dnf clean all

# 配置字体缓存和 locale
RUN fc-cache -fv

ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh

# 从 builder 复制应用（只复制源码和构建产物）
COPY --from=builder /app /app
WORKDIR /app

# 使用 builder 阶段已安装的完整依赖，无需重新安装
# 保留 pnpm 全局安装以便在容器内使用 pnpm 命令
RUN npm install -g pnpm@latest

# 创建 openclaw CLI 的软链接
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && \
    chmod 755 /app/openclaw.mjs

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