#!/usr/bin/env bash
# install-local.sh — 本地安装脚本（无需网络）
# 用法: bash install-local.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.claude/claude-model-scheduler"
BIN_DIR="${HOME}/.local/bin"
BIN_NAME="claude-model-scheduler"

# 颜色
_C_GREEN='\033[0;32m'
_C_CYAN='\033[0;36m'
_C_YELLOW='\033[0;33m'
_C_RED='\033[0;31m'
_C_BOLD='\033[1m'
_C_RESET='\033[0m'

info()  { printf "${_C_GREEN}[INFO]${_C_RESET} %s\n" "$*"; }
warn()  { printf "${_C_YELLOW}[WARN]${_C_RESET} %s\n" "$*"; }
error() { printf "${_C_RED}[ERROR]${_C_RESET} %s\n" "$*" >&2; }

main() {
    printf "\n${_C_BOLD}Claude Model Scheduler — 本地安装${_C_RESET}\n\n"

    # 检查 jq 或 python3
    if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
        error "需要 jq 或 python3 来处理 JSON"
        exit 1
    fi

    # 创建安装目录
    mkdir -p "${INSTALL_DIR}/lib"
    info "安装目录: ${INSTALL_DIR}"

    # 复制文件
    local files=(
        "claude-model-scheduler.sh"
        "lib/common.sh"
        "lib/config.sh"
        "lib/wizard.sh"
        "lib/scheduler_macos.sh"
        "lib/scheduler_linux.sh"
        "lib/scheduler_windows.sh"
        "lib/cleanup.sh"
    )

    info "复制文件..."
    for file in "${files[@]}"; do
        local src="${SCRIPT_DIR}/${file}"
        local dest="${INSTALL_DIR}/${file}"
        if [[ -f "$src" ]]; then
            cp "$src" "$dest"
            chmod +x "$dest"
        else
            error "文件不存在: ${file}"
            exit 1
        fi
    done

    # 创建 bin 目录和符号链接
    mkdir -p "$BIN_DIR"
    ln -sf "${INSTALL_DIR}/claude-model-scheduler.sh" "${BIN_DIR}/${BIN_NAME}"
    chmod +x "${BIN_DIR}/${BIN_NAME}"

    # 检查 PATH
    if ! echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
        local shell_rc=""
        case "$SHELL" in
            */zsh)  shell_rc="${HOME}/.zshrc" ;;
            */bash) shell_rc="${HOME}/.bashrc" ;;
            */fish) shell_rc="${HOME}/.config/fish/config.fish" ;;
        esac

        if [[ -n "$shell_rc" ]]; then
            echo "" >> "$shell_rc"
            echo '# Claude Model Scheduler' >> "$shell_rc"
            echo "export PATH=\"${BIN_DIR}:\$PATH\"" >> "$shell_rc"
            warn "已将 ${BIN_DIR} 添加到 PATH（${shell_rc}）"
            warn "请运行以下命令使 PATH 生效："
            printf "\n  ${_C_CYAN}source ${shell_rc}${_C_RESET}\n\n"
        else
            warn "请手动将 ${BIN_DIR} 添加到 PATH"
        fi
    fi

    info "文件部署完成！启动安装向导..."
    printf "\n"

    exec "${INSTALL_DIR}/claude-model-scheduler.sh" install < /dev/tty
}

main "$@"
