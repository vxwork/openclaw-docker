FROM almalinux:10.1-minimal
RUN if ! command -v dnf &> /dev/null; then microdnf install -y dnf; fi
RUN dnf install -y net-tools git curl python3 python3-pip tar glibc-langpack-zh && dnf clean all && \
    # generate Chinese locale to avoid locale warnings during `docker exec`
    localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true

# 安装中文字体支持并刷新缓存
# 添加常用中文字体包，包括文泉驿字体、Noto CJK 以及 DejaVu
# EPEL 提供的 Noto CJK 包名为 `fonts-noto-cjk`，不过也可以使用
# google-noto-sans-cjk-fonts。这里我们一并安装。
RUN dnf install -y fontconfig epel-release && \
    # enable CRB to satisfy some EPEL dependencies if needed
    dnf config-manager --set-enabled crb || true && \
    dnf makecache && \
    dnf install -y \
        wqy-zenhei-fonts \
        # microhei is not available in AlmaLinux/EPEL; zenhei provides Chinese support
        google-noto-sans-cjk-fonts \
        # pick a DejaVu family package, not "fonts-dejavu"
        dejavu-sans-fonts \
        # include all Noto fonts for completeness
        google-noto-fonts-all && \
    dnf clean all && \
    fc-cache -fv

# 安装 Node.js
RUN curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - && \
    dnf install -y nodejs && \
    node --version && npm --version
# 安装 pnpm
RUN npm install -g pnpm
# Git 配置
# 配置git全局设置
RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*"

WORKDIR /app

RUN git clone https://github.com/openclaw/openclaw.git .
# 安装依赖
RUN pnpm install && pnpm ui:build && pnpm build && pnpm openclaw setup &&  pnpm link --global
# 安装 Python 依赖
RUN pip install matplotlib numpy reportlab fpdf2 weasyprint

# 预配置 matplotlib 使用中文（镜像构建时生成，容器运行时由 entrypoint 进一步确认）
# 将常见中文字体放在 sans-serif 列表的前面，matplotlib 会按顺序
# 选择可用字体渲染中文。这里包含文泉驿 Zen Hei、Noto CJK 以及 DejaVu。
RUN mkdir -p /root/.config/matplotlib && \
    printf "font.family: sans-serif\nfont.sans-serif: WenQuanYi Zen Hei, Noto Sans CJK SC, DejaVu Sans\naxes.unicode_minus: False\n" \
        > /root/.config/matplotlib/matplotlibrc
        
EXPOSE 18789
# 设置环境变量
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# Copy entrypoint and make executable
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

