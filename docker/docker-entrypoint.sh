#!/bin/bash
set -e

# 确保 matplotlib 配置存在
if [ ! -f /root/.config/matplotlib/matplotlibrc ]; then
    mkdir -p /root/.config/matplotlib
    cat <<'EOF' >/root/.config/matplotlib/matplotlibrc
font.family: sans-serif
font.sans-serif: Noto Sans CJK SC, DejaVu Sans, sans-serif
axes.unicode_minus: False
EOF
    echo "✅ matplotlibrc 已生成（优先中文字体）"
fi

# ==================== 创建 openclaw 包装脚本 ====================
# 用于拦截 config 命令并自动修复路径问题
cat > /usr/local/bin/openclaw-wrapper <<'EOFWRAPPER'
#!/bin/bash

CONFIG_FILE="/root/.openclaw/openclaw.json"

# 如果是 config 相关命令，执行后修复配置文件
if [[ "$1" == "config" ]] || [[ "$*" == *"configure"* ]]; then
    echo "ℹ️ 使用 openclaw config 包装器（将自动修复路径问题）"
    # 执行原始的 openclaw 命令
    if command -v openclaw >/dev/null 2>&1; then
        openclaw "$@"
        exit_code=$?
    elif [ -f /app/package.json ] && command -v pnpm >/dev/null 2>&1; then
        pnpm openclaw "$@"
        exit_code=$?
    else
        echo "❌ 错误：找不到 openclaw 命令"
        exit 1
    fi
    
    # 如果命令成功执行，尝试修复配置文件
    if [ $exit_code -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
        echo "✅ config 命令执行成功，检查配置文件..."
        # 修复路径问题
        if grep -q '"extensionEntry": "\./index.js"' "$CONFIG_FILE" 2>/dev/null; then
            echo "⚠️ 检测到插件路径问题，正在修复..."
            sed -i 's|"extensionEntry": "\./index.js"|"extensionEntry": "index.js"|g' "$CONFIG_FILE"
            echo "✅ 配置文件路径已修复"
        fi
    fi
    
    exit $exit_code
else
    # 非 config 命令，直接转发
    if command -v openclaw >/dev/null 2>&1; then
        exec openclaw "$@"
    elif [ -f /app/package.json ] && command -v pnpm >/dev/null 2>&1; then
        exec pnpm openclaw "$@"
    else
        echo "❌ 错误：找不到 openclaw 命令"
        exit 1
    fi
fi
EOFWRAPPER

chmod +x /usr/local/bin/openclaw-wrapper

# 覆盖原始的 openclaw 命令
if command -v openclaw >/dev/null 2>&1; then
    # 备份原始命令
    OPENCLAW_PATH=$(which openclaw)
    echo "ℹ️ 备份原始 openclaw 命令位置：$OPENCLAW_PATH"
    # 创建包装脚本作为新的 openclaw 命令
    cat > /tmp/openclaw-wrapper-exec <<'EOFEXEC'
#!/bin/bash
exec /usr/local/bin/openclaw-wrapper "$@"
EOFEXEC
    chmod +x /tmp/openclaw-wrapper-exec
    # 修改 PATH 让包装脚本优先
    export PATH="/tmp:$PATH"
    echo "✅ 已设置 openclaw 包装器"
fi

# ==================== OpenClaw 配置与启动逻辑 ====================

CONFIG_DIR="/root/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
PAIRING_DIR="$CONFIG_DIR/pairing"
DEVICE_JSON="$PAIRING_DIR/device.json"

# 决定最终使用的 gateway token
if [ -n "${OPENCLAW_GATEWAY_TOKEN}" ]; then
    # 环境变量已定义 → 优先使用它（常见于 docker run -e 或 compose env_file）
    GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}"
    echo "ℹ️ 检测到环境变量 OPENCLAW_GATEWAY_TOKEN，使用它作为 gateway token"
else
    # 无环境变量 → 按原逻辑随机生成（仅首次）
    if [ ! -f "$DEVICE_JSON" ]; then
        echo "⚠️ 首次启动且无预设 token，进行初始化..."

        mkdir -p "$PAIRING_DIR"

        # 生成随机 token（优先 openssl，fallback urandom+sha256）
        if command -v openssl >/dev/null 2>&1; then
            GATEWAY_TOKEN=$(openssl rand -hex 32)
        else
            GATEWAY_TOKEN=$(head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1)
        fi

        # 写入 device.json（OpenClaw pairing 机制会用这个）
        cat > "$DEVICE_JSON" <<EOF
{
  "token": "$GATEWAY_TOKEN",
  "createdAt": "$(date -Iseconds)"
}
EOF
        echo "✅ 新生成的 gateway token：$GATEWAY_TOKEN （保存在 $DEVICE_JSON）"
    else
        # 已存在 pairing/device.json → 从中读取 token（避免重复生成）
        GATEWAY_TOKEN=$(jq -r '.token' "$DEVICE_JSON" 2>/dev/null || echo "")
        if [ -z "$GATEWAY_TOKEN" ]; then
            echo "❌ device.json 存在但无法读取 token，强制重新生成"
            GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1)
            jq --arg t "$GATEWAY_TOKEN" '.token = $t' "$DEVICE_JSON" > /tmp/device.json && mv /tmp/device.json "$DEVICE_JSON"
        fi
        echo "ℹ️ 从已有 device.json 读取 gateway token"
    fi
fi

# ==================== 启动参数准备 ====================

if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️ openclaw.json 不存在，首次启动允许未配置状态"
    #echo "setup feishu plugin"
    #npx -y @larksuite/openclaw-lark install
    # 检查是否应该跳过配置向导
    if [ "${OPENCLAW_SKIP_CONFIG:-false}" = "true" ]; then
        echo "ℹ️ OPENCLAW_SKIP_CONFIG=true，跳过配置向导直接启动"
        GATEWAY_ARGS="--allow-unconfigured --port 18789 --verbose --token ${GATEWAY_TOKEN}"
    else
        echo "ℹ️ 未设置 OPENCLAW_SKIP_CONFIG，将启动配置向导（如需跳过请设置 OPENCLAW_SKIP_CONFIG=true）"
        GATEWAY_ARGS="--allow-unconfigured --port 18789 --verbose --token ${GATEWAY_TOKEN}"
    fi
else
    echo "✅ openclaw.json 已存在，直接启动"
    GATEWAY_ARGS="--port 18789 --verbose --token ${GATEWAY_TOKEN}"
fi

# ==================== 执行启动（优先全局命令，兼容 pnpm 方式） ====================

if command -v openclaw >/dev/null 2>&1; then
    echo "ℹ️ 使用全局 openclaw 命令启动"
    exec openclaw gateway $GATEWAY_ARGS
elif [ -f /app/package.json ] && command -v pnpm >/dev/null 2>&1; then
    echo "ℹ️ 使用 pnpm openclaw 启动（源码模式）"
    exec pnpm openclaw gateway $GATEWAY_ARGS
else
    echo "❌ 错误：找不到 openclaw 命令（全局或 pnpm）"
    exit 1
fi
