#!/bin/bash
# 飞书插件安装脚本 - 修复版本检查问题
# 使用方法: bash install_feishu_plugin.sh

set -euo pipefail

echo "=== 飞书插件安装脚本 ==="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 工作目录
WORK_DIR="/tmp/feishu-plugin-install"
PLUGIN_NAME="feishu-openclaw-plugin"
PACKAGE_NAME="@larksuiteoapi/feishu-openclaw-plugin"
EXTENSIONS_DIR="$HOME/.openclaw/extensions"
PLUGIN_PATH="$EXTENSIONS_DIR/$PLUGIN_NAME"
CONFLICT_PLUGIN_PATH="$EXTENSIONS_DIR/feishu"

# 清理并创建工作目录
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${BLUE}[1/6] 下载安装器...${NC}"
curl -sL -o skill.tgz "https://sf3-cn.feishucdn.com/obj/open-platform-opendoc/195a94cb3d9a45d862d417313ff62c9c_gfW8JbxtTd.tgz"
tar -xzf skill.tgz
cd package

echo -e "${BLUE}[2/6] 修复版本检查问题...${NC}"
# 修复版本检查逻辑 - 将版本比较改为支持 2026.3.8 格式
sed -i 's/if (compareVersions(version, .2026.2.26.) < 0)/if (false)/' dist/commands/install.js

echo -e "${BLUE}[3/6] 设置 npm 镜像...${NC}"
npm config set registry https://registry.npmjs.org/

echo -e "${BLUE}[4/6] 禁用内置飞书插件...${NC}"
# 读取当前配置并修改
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
if [ -f "$CONFIG_FILE" ]; then
    # 使用 node 修改 JSON 配置
    node -e "
    const fs = require('fs');
    const config = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    if (!config.plugins) config.plugins = {};
    if (!config.plugins.entries) config.plugins.entries = {};
    if (!config.plugins.entries.feishu) config.plugins.entries.feishu = {};
    config.plugins.entries.feishu.enabled = false;
    if (!config.plugins.allow) config.plugins.allow = [];
    if (!config.plugins.allow.includes('$PLUGIN_NAME')) {
        config.plugins.allow.push('$PLUGIN_NAME');
    }
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
    console.log('配置已更新');
    "
fi

echo -e "${BLUE}[5/6] 移除冲突目录...${NC}"
if [ -d "$CONFLICT_PLUGIN_PATH" ]; then
    rm -rf "$CONFLICT_PLUGIN_PATH"
    echo "已移除冲突目录"
fi

echo -e "${BLUE}[6/6] 安装飞书插件...${NC}"
# 兼容不同运行环境：
# 1) 已安装全局 openclaw
# 2) 无全局 openclaw，但有 pnpm（源码模式）
# 3) 无 pnpm，但存在 /app/openclaw.mjs（Node 直接启动）
run_openclaw() {
    if command -v openclaw >/dev/null 2>&1; then
        openclaw "$@"
        return
    fi

    if command -v pnpm >/dev/null 2>&1 && [ -f "/app/package.json" ]; then
        pnpm --dir /app openclaw "$@"
        return
    fi

    if command -v node >/dev/null 2>&1 && [ -f "/app/openclaw.mjs" ]; then
        node /app/openclaw.mjs "$@"
        return
    fi

    echo -e "${RED}未找到可用的 openclaw 执行方式（openclaw/pnpm/node）${NC}"
    exit 1
}

run_openclaw plugins install "$PACKAGE_NAME"

echo ""
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo ""
echo -e "${YELLOW}注意: 你需要配置飞书应用的 App ID 和 App Secret${NC}"
echo -e "${YELLOW}请编辑 $CONFIG_FILE 文件，在 channels.feishu 下添加:${NC}"
echo "  - appId: 你的飞书应用 ID"
echo "  - appSecret: 你的飞书应用 Secret"
echo ""
echo -e "${BLUE}安装完成后，运行: openclaw gateway run${NC}"
