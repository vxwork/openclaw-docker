# syntax=docker/dockerfile:1.7

ARG OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
ARG OPENCLAW_REF="main"
ARG OPENCLAW_EXTENSIONS=""
ARG OPENCLAW_BUNDLED_PLUGIN_DIR="extensions"
ARG OPENCLAW_NODE_IMAGE="docker.io/library/node:24-bookworm"
ARG OPENCLAW_BUN_IMAGE="docker.io/oven/bun:1.3.13"

FROM ${OPENCLAW_BUN_IMAGE} AS bun-binary

FROM ${OPENCLAW_NODE_IMAGE} AS build
ARG OPENCLAW_REPO
ARG OPENCLAW_REF
ARG OPENCLAW_EXTENSIONS
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

ENV OPENCLAW_PREFER_PNPM=1

COPY --from=bun-binary /usr/local/bin/bun /usr/local/bin/bun

RUN corepack enable

WORKDIR /app

RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*" \
    && git clone --depth 1 --branch "$OPENCLAW_REF" "$OPENCLAW_REPO" .

RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile \
        --config.supportedArchitectures.os=linux \
        --config.supportedArchitectures.cpu="$(node -p 'process.arch')" \
        --config.supportedArchitectures.libc=glibc

RUN set -eux; \
    if ! printf '%s\n' "$OPENCLAW_EXTENSIONS" | tr ',' ' ' | tr ' ' '\n' | grep -qx 'matrix'; then \
        echo "==> matrix not bundled, skipping matrix-sdk-crypto check"; \
        exit 0; \
    fi; \
    echo "==> Verifying critical native addons..."; \
    for attempt in 1 2 3 4 5; do \
        if find /app/node_modules -name "matrix-sdk-crypto*.node" 2>/dev/null | grep -q .; then \
            exit 0; \
        fi; \
        echo "matrix-sdk-crypto native addon missing; retrying download (${attempt}/5)"; \
        node /app/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/download-lib.js || true; \
        sleep $((attempt * 2)); \
    done; \
    find /app/node_modules -name "matrix-sdk-crypto*.node" 2>/dev/null | grep -q . || \
        (echo "ERROR: matrix-sdk-crypto native addon missing after retries" >&2 && exit 1)

RUN for dir in /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} /app/.agent /app/.agents; do \
        if [ -d "$dir" ]; then \
            find "$dir" -type d -exec chmod 755 {} +; \
            find "$dir" -type f -exec chmod 644 {} +; \
        fi; \
    done

RUN pnpm_config_verify_deps_before_run=false pnpm canvas:a2ui:bundle || \
    (echo "A2UI bundle: creating stub (non-fatal)" && \
        mkdir -p extensions/canvas/src/host/a2ui && \
        echo "/* A2UI bundle unavailable in this build */" > extensions/canvas/src/host/a2ui/a2ui.bundle.js && \
        echo "stub" > extensions/canvas/src/host/a2ui/.bundle.hash && \
        rm -rf vendor/a2ui apps/shared/OpenClawKit/Tools/CanvasA2UI)

RUN NODE_OPTIONS=--max-old-space-size=8192 pnpm_config_verify_deps_before_run=false pnpm build:docker
RUN pnpm_config_verify_deps_before_run=false pnpm ui:build
RUN pnpm_config_verify_deps_before_run=false pnpm qa:lab:build

FROM build AS runtime-assets
ARG OPENCLAW_EXTENSIONS
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    pnpm list --prod --depth Infinity --json | node scripts/list-prod-store-packages.mjs | xargs -r pnpm store add && \
    CI=true pnpm prune --prod \
        --config.offline=true \
        --config.supportedArchitectures.os=linux \
        --config.supportedArchitectures.cpu="$(node -p 'process.arch')" \
        --config.supportedArchitectures.libc=glibc && \
    OPENCLAW_EXTENSIONS="$OPENCLAW_EXTENSIONS" OPENCLAW_BUNDLED_PLUGIN_DIR="$OPENCLAW_BUNDLED_PLUGIN_DIR" node scripts/prune-docker-plugin-dist.mjs && \
    node scripts/postinstall-bundled-plugins.mjs && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete && \
    node scripts/check-package-dist-imports.mjs /app

FROM almalinux:10.2-minimal
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

LABEL org.opencontainers.image.source="https://github.com/vxwork/openclaw-docker" \
      org.opencontainers.image.title="OpenClaw AlmaLinux runtime" \
      org.opencontainers.image.description="OpenClaw gateway and CLI runtime container image based on AlmaLinux 10.2 minimal"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN if ! command -v dnf >/dev/null 2>&1; then microdnf install -y dnf; fi

RUN dnf install -y \
        bash \
        ca-certificates \
        curl \
        dnf-plugins-core \
        epel-release \
        findutils \
        fontconfig \
        git \
        glibc-langpack-zh \
        hostname \
        jq \
        lsof \
        net-tools \
        openssl \
        pango \
        procps-ng \
        python3 \
        python3-pip \
        shadow-utils \
        tar \
        xz \
    && (dnf config-manager --set-enabled crb || true) \
    && dnf makecache \
    && dnf install -y \
        dejavu-sans-fonts \
        google-noto-fonts-all \
        google-noto-sans-cjk-fonts \
        wqy-zenhei-fonts \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true \
    && fc-cache -fv

RUN curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - \
    && dnf install -y nodejs \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && node --version \
    && npm --version

WORKDIR /app

COPY --from=runtime-assets /app/dist ./dist
COPY --from=runtime-assets /app/node_modules ./node_modules
COPY --from=runtime-assets /app/package.json .
COPY --from=runtime-assets /app/pnpm-workspace.yaml .
COPY --from=runtime-assets /app/patches ./patches
COPY --from=runtime-assets /app/openclaw.mjs .
COPY --from=runtime-assets /app/src/agents/templates ./src/agents/templates
COPY --from=runtime-assets /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} ./${OPENCLAW_BUNDLED_PLUGIN_DIR}
COPY --from=runtime-assets /app/skills ./skills
COPY --from=runtime-assets /app/docs ./docs
COPY --from=runtime-assets /app/qa ./qa

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw \
    && chmod 755 /app/openclaw.mjs \
    && openclaw --version

ENV COREPACK_HOME=/usr/local/share/corepack
RUN install -d -m 0755 "$COREPACK_HOME" \
    && corepack enable \
    && for attempt in 1 2 3 4 5; do \
        if corepack prepare "$(node -p "require('./package.json').packageManager")" --activate; then \
            break; \
        fi; \
        if [ "$attempt" -eq 5 ]; then \
            exit 1; \
        fi; \
        sleep $((attempt * 2)); \
    done \
    && chmod -R a+rX "$COREPACK_HOME"

RUN python3 -m pip install --no-cache-dir --break-system-packages \
        matplotlib \
        numpy \
        reportlab \
        fpdf2 \
        weasyprint \
    || python3 -m pip install --no-cache-dir \
        matplotlib \
        numpy \
        reportlab \
        fpdf2 \
        weasyprint

RUN mkdir -p /root/.config/matplotlib && \
    printf "font.family: sans-serif\nfont.sans-serif: WenQuanYi Zen Hei, Noto Sans CJK SC, DejaVu Sans, sans-serif\naxes.unicode_minus: False\n" \
        > /root/.config/matplotlib/matplotlibrc

ENV LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    NODE_ENV=production

EXPOSE 18789

COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["gateway"]
