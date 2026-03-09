FROM almalinux:10.1-minimal AS builder

RUN if ! command -v dnf >/dev/null 2>&1; then microdnf install -y dnf; fi
RUN dnf install -y --setopt=install_weak_deps=False --nodocs git curl nodejs npm \
    && dnf clean all
RUN npm install -g pnpm && npm cache clean --force

WORKDIR /app

RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*"

RUN git clone --depth 1 https://github.com/openclaw/openclaw.git . \
    && pnpm install \
    && pnpm ui:build \
    && pnpm build \
    && pnpm openclaw setup \
    && pnpm prune --prod \
    && rm -rf .git /root/.npm /root/.cache /root/.local/share/pnpm/store

FROM almalinux:10.1-minimal

RUN if ! command -v dnf >/dev/null 2>&1; then microdnf install -y dnf; fi
RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
        net-tools \
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
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true \
    && fc-cache -fv

RUN npm install -g pnpm && npm cache clean --force

WORKDIR /app
COPY --from=builder /app /app

RUN pip install --no-cache-dir matplotlib numpy reportlab fpdf2 weasyprint

RUN mkdir -p /root/.config/matplotlib && \
    printf "font.family: sans-serif\nfont.sans-serif: Noto Sans CJK SC, DejaVu Sans\naxes.unicode_minus: False\n" \
        > /root/.config/matplotlib/matplotlibrc

EXPOSE 18789
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

