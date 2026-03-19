FROM almalinux:10.1-minimal AS base

# 确保 dnf 可用
RUN if ! command -v dnf &> /dev/null; then \
        microdnf install -y dnf; \
    fi

# 添加构建参数支持 GitHub Token 认证
ARG GITHUB_TOKEN=

# 安装基础系统工具和依赖
RUN dnf install -y \
    curl \
    python3 \
    python3-pip \
    tar \
    glibc-langpack-zh \
    fontconfig \
    epel-release && \
    # 启用 CRB 仓库（原 PowerTools）
    dnf config-manager --set-enabled crb || true && \
    dnf makecache && \
    # 安装中文字体支持
    dnf install -y \
        google-noto-sans-cjk-fonts \
        dejavu-sans-fonts && \
    # 清理包管理器缓存以减小镜像大小
    dnf clean all && \
    # 配置中文 locale
    localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true && \
    # 刷新字体缓存
    fc-cache -fv

FROM base AS node-base

RUN curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - && \
    dnf install -y nodejs && \
    npm install -g pnpm && \
    dnf clean all && \
    node --version && npm --version && pnpm --version

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
WORKDIR /app

FROM node-base AS builder

# 设置非交互式环境
ENV CI=true

# 安装 git 并清理缓存
RUN dnf install -y git && dnf clean all

# 配置 git 全局设置，确保 HTTPS 替代 SSH，避免密钥问题
RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*" \
    && git config --global http.postBuffer 524288000 \
    && git config --global http.lowSpeedLimit 0 \
    && git config --global http.lowSpeedTime 999999

# 克隆 OpenClaw 仓库（支持私有仓库认证）
RUN if [ -n "$GITHUB_TOKEN" ]; then \
        echo "Using GitHub token authentication for private repository"; \
        git clone --depth 1 https://${GITHUB_TOKEN}@github.com/openclaw/openclaw.git . ; \
    else \
        echo "Attempting to clone public repository..."; \
        git clone --depth 1 https://github.com/openclaw/openclaw.git . || { \
            echo ""; \
            echo "==========================================="; \
            echo "ERROR: Failed to clone repository!"; \
            echo "==========================================="; \
            echo "Possible reasons:"; \
            echo "1. Repository is private - use --build-arg GITHUB_TOKEN=<your_token>"; \
            echo "2. Repository URL is incorrect"; \
            echo "3. Network connectivity issues"; \
            echo ""; \
            echo "Example build command:"; \
            echo "docker build --build-arg GITHUB_TOKEN=ghp_xxxxx ."; \
            echo "==========================================="; \
            exit 1; \
        } \
    fi

# 复制并应用必要的补丁（修复 extension entry escapes package directory 错误）
COPY docker/patches/openclaw-discovery-entry-not-found.patch /tmp/openclaw-discovery-entry-not-found.patch
RUN git apply /tmp/openclaw-discovery-entry-not-found.patch && rm /tmp/openclaw-discovery-entry-not-found.patch

# 安装依赖、构建项目并进行初始化设置
# 分步执行以便更好地定位构建失败环节
RUN pnpm install && \
    pnpm ui:build && \
    pnpm build && \
    pnpm openclaw setup && \
    # 移除开发依赖以减小生产镜像大小
    pnpm prune --prod && \
    # 清理版本控制和 CI/CD 相关文件
    rm -rf .git .github

FROM node-base AS runtime

RUN dnf install -y jq openssl && dnf clean all

WORKDIR /app
COPY --from=builder /app /app

# 将 openclaw 加入 PATH：用 wrapper 调用 pnpm openclaw（因 CLI 可能来自 script 而非 node_modules/.bin）
RUN printf '%s\n' '#!/bin/sh' 'exec pnpm --dir /app openclaw "$@"' > /usr/local/bin/openclaw && chmod +x /usr/local/bin/openclaw

# 安装 Python 依赖
RUN pip install --no-cache-dir matplotlib numpy reportlab fpdf2 weasyprint

# 预配置 matplotlib 使用中文，并创建 OpenClaw 编译缓存目录
RUN mkdir -p /root/.config/matplotlib /var/tmp/openclaw-compile-cache && \
    printf "font.family: sans-serif\nfont.sans-serif: Noto Sans CJK SC, DejaVu Sans\naxes.unicode_minus: False\n" > /root/.config/matplotlib/matplotlibrc

EXPOSE 18789

# 设置环境变量
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
# OpenClaw 性能优化：启用编译缓存并禁用自重启机制，减少资源开销
ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
ENV OPENCLAW_NO_RESPAWN=1

# 复制入口脚本并赋予可执行权限
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 使用自定义入口点启动应用
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

