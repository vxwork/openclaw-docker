FROM almalinux:10.1-minimal AS base

RUN if ! command -v dnf &> /dev/null; then microdnf install -y dnf; fi
RUN dnf install -y \
    curl \
    python3 \
    python3-pip \
    tar \
    glibc-langpack-zh \
    fontconfig \
    epel-release && \
    dnf config-manager --set-enabled crb || true && \
    dnf makecache && \
    dnf install -y \
        google-noto-sans-cjk-fonts \
        dejavu-sans-fonts && \
    dnf clean all && \
    localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true && \
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

ENV CI=true
RUN dnf install -y git && dnf clean all
RUN git clone https://github.com/openclaw/openclaw.git . && \
    pnpm install && \
    pnpm ui:build && \
    pnpm build && \
    pnpm openclaw setup && \
    pnpm prune --prod && \
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
# OpenClaw 低功耗/小主机建议：编译缓存 + 禁用自重启，减少开销
ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
ENV OPENCLAW_NO_RESPAWN=1

# Copy entrypoint and make executable
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

