FROM almalinux:10.1-minimal

# 先确保dnf可用，如果不存在则安装
RUN if ! command -v dnf &> /dev/null; then \
        microdnf install -y dnf; \
    fi

# 安装基础工具
RUN dnf install -y \
    net-tools \
    git \
    && dnf clean all

# 从NodeSource安装最新Node.js
RUN curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - \
    && dnf install -y nodejs \
    && node --version \
    && npm --version

# 安装pnpm最新版本
RUN npm install -g pnpm

# 配置git全局设置
RUN git config --global --add url."https://github.com/".insteadOf git@github.com: \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:/ \
    && git config --global --add safe.directory "*"

# 创建工作目录
WORKDIR /app

# 克隆QVerisBot仓库
RUN git clone https://github.com/openclaw/openclaw.git .

# 安装依赖并构建（分离插件安装）
RUN pnpm install \
    && pnpm ui:build \
    && pnpm build \
    && pnpm openclaw setup

# 单独安装feishu插件，添加错误处理
#RUN pnpm openclaw plugins install @openclaw/feishu || echo "Warning: feishu plugin installation failed, continuing..."

# 暴露端口
EXPOSE 18789

# 启动命令改为sleep infinity便于调试
CMD ["sleep", "infinity"]
