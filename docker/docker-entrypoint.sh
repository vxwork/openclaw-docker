#!/usr/bin/env bash
set -euo pipefail

# ==================== 配置路径（Docker 中建议使用 /root/.openclaw 或挂载卷） ====================
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
PAIRING_DIR="${CONFIG_DIR}/pairing"
DEVICE_JSON="${PAIRING_DIR}/device.json"

# ==================== 日志辅助函数（更统一、支持级别） ====================
log_info()  { echo "ℹ️  ${*}" >&2; }
log_warn()  { echo "⚠️  ${*}" >&2; }
log_error() { echo "❌  ${*}" >&2; }
log_success() { echo "✅  ${*}" >&2; }

# ==================== 生成随机 token 的函数（更健壮） ====================
generate_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    elif command -v head && command -v sha256sum >/dev/null 2>&1; then
        head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1
    else
        log_error "无法生成安全 token：缺少 openssl 或 urandom+sha256sum"
        exit 1
    fi
}

# ==================== 处理 gateway token 逻辑 ====================
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}"
    log_info "使用环境变量 OPENCLAW_GATEWAY_TOKEN 作为 gateway token"
else
    mkdir -p "${PAIRING_DIR}" || { log_error "无法创建 pairing 目录"; exit 1; }

    if [ ! -f "${DEVICE_JSON}" ]; then
        log_warn "首次启动，无预设 token，进行初始化..."

        GATEWAY_TOKEN=$(generate_token)

        jq -n --arg t "${GATEWAY_TOKEN}" --arg ts "$(date -Iseconds)" \
            '{token: $t, createdAt: $ts}' > "${DEVICE_JSON}" || {
            log_error "写入 device.json 失败（jq 可能缺失或权限问题）"
            exit 1
        }

        log_success "已生成并保存新的 gateway token 到 ${DEVICE_JSON}"
    else
        if ! GATEWAY_TOKEN=$(jq -r '.token // empty' "${DEVICE_JSON}" 2>/dev/null); then
            log_warn "device.json 存在但解析失败，强制重新生成 token"
            GATEWAY_TOKEN=$(generate_token)
            jq --arg t "${GATEWAY_TOKEN}" '.token = $t' "${DEVICE_JSON}" > "${DEVICE_JSON}.tmp" &&
                mv "${DEVICE_JSON}.tmp" "${DEVICE_JSON}" || {
                log_error "更新 device.json 失败"
                exit 1
            }
        fi
        log_info "从已有 ${DEVICE_JSON} 读取 gateway token"
    fi
fi

# ==================== 准备 gateway 启动参数 ====================
GATEWAY_ARGS=(
    "--port"    "${OPENCLAW_GATEWAY_PORT:-18789}"
    "--verbose"
    "--token"   "${GATEWAY_TOKEN}"
)

# 可选：支持更多环境变量覆盖（推荐做法）
[ -n "${OPENCLAW_GATEWAY_BIND:-}" ]     && GATEWAY_ARGS+=("--bind"     "${OPENCLAW_GATEWAY_BIND}")
[ -n "${OPENCLAW_GATEWAY_WS_LOG:-}" ]   && GATEWAY_ARGS+=("--ws-log"   "${OPENCLAW_GATEWAY_WS_LOG}")

if [ ! -f "${CONFIG_FILE}" ]; then
    log_warn "openclaw.json 不存在（首次启动允许未配置状态）"

    if [ "${OPENCLAW_SKIP_CONFIG:-true}" = "true" ]; then
        log_info "OPENCLAW_SKIP_CONFIG=true → 跳过配置向导，直接启动"
        GATEWAY_ARGS+=("--allow-unconfigured")
    else
        log_info "未设置 OPENCLAW_SKIP_CONFIG → 将尝试启动（可能进入配置流程）"
        GATEWAY_ARGS+=("--allow-unconfigured")
    fi
else
    log_success "openclaw.json 已存在 → 正常启动"
fi

# ==================== 执行启动 ====================
if command -v openclaw >/dev/null 2>&1; then
    log_info "使用全局 openclaw 命令启动"
    exec openclaw gateway "${GATEWAY_ARGS[@]}"
elif [ -f "/app/package.json" ] && command -v pnpm >/dev/null 2>&1; then
    log_info "使用 pnpm 执行 openclaw（源码/开发模式）"
    exec pnpm openclaw gateway "${GATEWAY_ARGS[@]}"
else
    log_error "找不到 openclaw 命令（全局安装或 pnpm 方式均不可用）"
    log_error "当前 PATH: ${PATH}"
    log_error "请检查 Dockerfile 是否正确安装了 openclaw CLI"
    exit 1
fi