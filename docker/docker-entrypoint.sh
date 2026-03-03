#!/bin/bash
set -e

# 确保 matplotlib 配置存在（构建时可能创建，但运行时检查更保险）
if [ ! -f /root/.config/matplotlib/matplotlibrc ]; then
    mkdir -p /root/.config/matplotlib
    cat <<'EOF' >/root/.config/matplotlib/matplotlibrc
font.family: sans-serif
font.sans-serif: Noto Sans CJK SC, DejaVu Sans
axes.unicode_minus: False
EOF
    echo "✅ 已生成 /root/.config/matplotlib/matplotlibrc"
fi

# Check for necessary configuration
if [ ! -f /root/.openclaw/openclaw.json ]; then
    echo "⚠️ 配置文件不存在，首次启动需要初始化配置..."
    # Create default config directories
    mkdir -p /root/.openclaw/workspace
    mkdir -p /root/.openclaw/pairing

    # Generate device token
    DEVICE_TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "{\"token\":\"$DEVICE_TOKEN\",\"createdAt\":\"$(date -Iseconds)\"}" > /root/.openclaw/pairing/device.json

    echo "✅ 已生成设备令牌"

    exec pnpm openclaw gateway --allow-unconfigured --port 18789 --verbose
else
    echo "✅ 配置文件已存在，跳过初始化"
    exec pnpm openclaw gateway --port 18789 --verbose
fi
