FROM almalinux:10.1-minimal AS builder

RUN if ! command -v dnf >/dev/null 2>&1; then microdnf install -y dnf; fi \
    && dnf install -y --setopt=install_weak_deps=False --nodocs git curl bash nodejs npm \
    && npm install -g pnpm \
    && npm cache clean --force \
    && dnf clean all

WORKDIR /app

RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*"

RUN git clone https://github.com/openclaw/openclaw.git . \
    && CI=true pnpm install \
    && CI=true pnpm ui:build \
    && CI=true OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build:docker \
    && CI=true pnpm openclaw setup \
    && CI=true pnpm prune --prod \
    && rm -rf .git /root/.npm /root/.cache /root/.local/share/pnpm/store

FROM almalinux:10.1-minimal

RUN if ! command -v dnf >/dev/null 2>&1; then microdnf install -y dnf; fi \
    && dnf install -y --setopt=install_weak_deps=False --nodocs \
        net-tools \
        which \
        ncurses \
        curl \
        openssl \
        jq \
        python3 \
        python3-pip \
        tar \
        glibc-langpack-zh \
        fontconfig \
        epel-release \
    && (dnf config-manager --set-enabled crb || true) \
    && dnf makecache \
    && dnf install -y --setopt=install_weak_deps=False --nodocs \
        google-noto-sans-cjk-fonts \
        dejavu-sans-fonts \
        nodejs \
        npm \
    && npm install -g pnpm \
    && npm cache clean --force \
    && pip install --no-cache-dir matplotlib numpy reportlab fpdf2 weasyprint \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && (localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true) \
    && fc-cache -fv

WORKDIR /app
COPY --from=builder /app /app

RUN mkdir -p /root/.config/matplotlib && \
    printf "font.family: sans-serif\nfont.sans-serif: Noto Sans CJK SC, DejaVu Sans\naxes.unicode_minus: False\n" \
        > /root/.config/matplotlib/matplotlibrc

EXPOSE 18789
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV TERM=xterm-256color

COPY docker/docker-entrypoint.sh docker/install_feishu_plugin.sh /usr/local/bin/
RUN printf '#!/bin/sh\nif [ "${1:-}" = "tui" ]; then\n  unset CI\n  export NODE_ENV=development\n  export TERM="${TERM:-xterm-256color}"\nfi\nexec node /app/openclaw.mjs "$@"\n' > /usr/local/bin/openclaw \
    && chmod +x /usr/local/bin/openclaw /usr/local/bin/docker-entrypoint.sh /usr/local/bin/install_feishu_plugin.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

