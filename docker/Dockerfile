FROM almalinux:10.1-minimal

# Ensure dnf/microdnf is available and install basic tools
RUN if ! command -v dnf &> /dev/null; then \
        microdnf install -y dnf; \
    fi && \
    dnf install -y \
        net-tools \
        git \
        curl \
        bash \
    && dnf clean all

# Install Node.js from NodeSource and pnpm
RUN curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - \
    && dnf install -y nodejs \
    && npm --version \
    && node --version \
    && npm install -g pnpm@latest

# Configure git to prefer https and allow safe directory
RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*"

WORKDIR /app

# Clone OpenClaw repository
RUN git clone https://github.com/openclaw/openclaw.git .

# Install dependencies and build
RUN pnpm install \
    && pnpm ui:build \
    && pnpm build \
    && pnpm openclaw setup

EXPOSE 18789

# Copy entrypoint and make executable
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

