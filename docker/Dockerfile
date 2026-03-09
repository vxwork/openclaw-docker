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

RUN dnf install -y git && dnf clean all
RUN git clone https://github.com/openclaw/openclaw.git . && \
    pnpm install && \
    pnpm ui:build && \
    pnpm build && \
    pnpm openclaw setup

FROM node-base AS runtime

RUN dnf install -y net-tools jq openssl && dnf clean all

WORKDIR /app
COPY --from=builder /app /app

# 安装 Python 依赖
RUN pip install matplotlib numpy reportlab fpdf2 weasyprint

# 预配置 matplotlib 使用中文
RUN mkdir -p /root/.config/matplotlib && \
    printf "font.family: sans-serif\nfont.sans-serif: Noto Sans CJK SC, DejaVu Sans\naxes.unicode_minus: False\n" > /root/.config/matplotlib/matplotlibrc

EXPOSE 18789

# 设置环境变量
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# Copy entrypoint and make executable
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

