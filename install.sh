#!/usr/bin/env bash
# install.sh — 一键远程安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/yourname/claude-model-scheduler/main/install.sh | bash
set -euo pipefail

REPO="shellery1988/claude-model-scheduler"
BRANCH="main"
INSTALL_DIR="${HOME}/.claude/claude-model-scheduler"
BIN_DIR="${HOME}/.local/bin"
BIN_NAME="claude-model-scheduler"

# 颜色
_C_GREEN='\033[0;32m'
_C_CYAN='\033[0;36m'
_C_RED='\033[0;31m'
_C_BOLD='\033[1m'
_C_RESET='\033[0m'

info()  { printf "${_C_GREEN}[INFO]${_C_RESET} %s\n" "$*"; }
warn()  { printf "${_C_CYAN}[WARN]${_C_RESET} %s\n" "$*"; }
error() { printf "${_C_RED}[ERROR]${_C_RESET} %s\n" "$*" >&2; }

# 选择下载工具
detect_downloader() {
    if command -v curl &>/dev/null; then
        echo "curl"
    elif command -v wget &>/dev/null; then
        echo "wget"
    else
        return 1
    fi
}

# 下载文件到指定路径
download() {
    local url="$1" dest="$2"
    case "$DOWNLOADER" in
        curl) curl -fsSL "$url" -o "$dest" ;;
        wget) wget -qO "$dest" "$url" ;;
    esac
}

main() {
    printf "\n${_C_BOLD}Claude Model Scheduler — 一键安装${_C_RESET}\n\n"

    # 检查下载工具
    DOWNLOADER="$(detect_downloader)" || {
        error "需要 curl 或 wget"
        exit 1
    }

    # 检查 jq 或 python3
    if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
        error "需要 jq 或 python3 来处理 JSON"
        exit 1
    fi

    # 确定下载源（GitHub 或 Gitee 镜像）
    local base_url="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
    info "下载源: ${base_url}"

    # 创建安装目录
    mkdir -p "${INSTALL_DIR}/lib"
    info "安装目录: ${INSTALL_DIR}"

    # 下载文件列表
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

    info "下载文件..."
    local failed=0
    for file in "${files[@]}"; do
        local dest="${INSTALL_DIR}/${file}"
        if download "${base_url}/${file}" "$dest"; then
            chmod +x "$dest"
        else
            error "下载失败: ${file}"
            ((failed++))
        fi
    done

    if (( failed > 0 )); then
        error "${failed} 个文件下载失败，请检查网络或仓库地址"
        exit 1
    fi

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

    info "安装完成！"
    printf "\n"
    printf "  ${_C_BOLD}使用方式：${_C_RESET}\n"
    printf "    ${_C_CYAN}claude-model-scheduler install${_C_RESET}    # 启动配置向导\n"
    printf "    ${_C_CYAN}claude-model-scheduler switch sonnet${_C_RESET}  # 手动切换\n"
    printf "    ${_C_CYAN}claude-model-scheduler status${_C_RESET}       # 查看状态\n"
    printf "\n"

    # 如果 PATH 已生效，直接启动向导
    if echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
        exec claude-model-scheduler install
    fi
}

main "$@"
