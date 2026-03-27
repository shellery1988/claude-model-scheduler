#!/usr/bin/env bash
# claude-model-scheduler.sh — Claude 模型定时切换器主入口
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 支持符号链接：如果 SCRIPT_DIR 没有 lib/，尝试解析真实路径
if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null)")" && pwd)"
fi
LIB_DIR="${SCRIPT_DIR}/lib"

# 加载通用函数库
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/config.sh"

# ── 子命令处理 ────────────────────────────────────────────

cmd_help() {
    if [[ $_COLOR_ENABLED -eq 1 ]]; then
        print_color "
${_C_BOLD}Claude Model Scheduler${_C_RESET} — Claude 模型定时切换器

${_C_BOLD}用法:${_C_RESET}
  claude-model-scheduler.sh <命令> [选项]

${_C_BOLD}命令:${_C_RESET}
  ${_C_CYAN}install${_C_RESET}              交互式安装向导（设置调度任务）
  ${_C_CYAN}uninstall${_C_RESET}            卸载调度任务（可选清理配置）
  ${_C_CYAN}status${_C_RESET}               显示调度任务状态和最近记录
  ${_C_CYAN}switch${_C_RESET} <model>       手动切换模型（opus/sonnet/haiku）
  ${_C_CYAN}help${_C_RESET}                 显示此帮助信息

${_C_BOLD}示例:${_C_RESET}
  claude-model-scheduler.sh install
  claude-model-scheduler.sh switch sonnet
  claude-model-scheduler.sh status
  claude-model-scheduler.sh uninstall

${_C_BOLD}配置文件:${_C_RESET}
  ~/.claude/scheduler.d/config.json
"
    else
        cat <<'HELP'
Claude Model Scheduler — Claude 模型定时切换器

用法:
  claude-model-scheduler.sh <命令> [选项]

命令:
  install              交互式安装向导（设置调度任务）
  uninstall            卸载调度任务（可选清理配置）
  status               显示调度任务状态和最近记录
  switch <model>       手动切换模型（opus/sonnet/haiku）
  help                 显示此帮助信息

示例:
  claude-model-scheduler.sh install
  claude-model-scheduler.sh switch sonnet
  claude-model-scheduler.sh status
  claude-model-scheduler.sh uninstall

配置文件:
  ~/.claude/scheduler.d/config.json
HELP
    fi
}

cmd_switch() {
    local model="${1:-}"
    if [[ -z "$model" ]]; then
        log_error "请指定模型: opus / sonnet / haiku"
        echo "用法: claude-model-scheduler.sh switch <model>"
        exit 1
    fi

    model="$(resolve_model_name "$model")"
    if ! get_model_env_key "$model" &>/dev/null; then
        log_error "未知模型: $model"
        echo "可选模型: opus, sonnet, haiku"
        exit 1
    fi

    TRIGGER="manual" do_switch "$model"
}

cmd_status() {
    print_color "\n${_C_BOLD}═══ Claude Model Scheduler 状态 ═══${_C_RESET}\n"
    echo ""
    show_config

    # 加载对应平台的调度器并显示状态
    local os
    os="$(detect_os)"
    case "$os" in
        macos)   source "${LIB_DIR}/scheduler_macos.sh"   ;;
        linux)   source "${LIB_DIR}/scheduler_linux.sh"   ;;
        windows) source "${LIB_DIR}/scheduler_windows.sh" ;;
        *)       log_warn "不支持的操作系统: $os" ;;
    esac
    scheduler_status

    echo ""
    show_recent_history 10
}

cmd_install() {
    source "${LIB_DIR}/wizard.sh"
    wizard_run
}

cmd_uninstall() {
    local os
    os="$(detect_os)"
    case "$os" in
        macos)   source "${LIB_DIR}/scheduler_macos.sh"   ;;
        linux)   source "${LIB_DIR}/scheduler_linux.sh"   ;;
        windows) source "${LIB_DIR}/scheduler_windows.sh" ;;
        *)       log_error "不支持的操作系统: $os"; exit 1 ;;
    esac

    if [[ ! -f "$SCHEDULER_CONFIG" ]]; then
        log_warn "尚未安装调度任务"
        exit 0
    fi

    scheduler_uninstall
    log_info "调度任务已卸载"

    if ask_confirm "是否同时清理配置和历史记录？"; then
        rm -rf "$SCHEDULER_CONFIG_DIR"
        log_info "配置和历史记录已清理"
    else
        log_info "配置文件保留在 ${SCHEDULER_CONFIG_DIR}/"
    fi
}

# ── 主入口 ────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        install)   cmd_install "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        status)    cmd_status "$@" ;;
        switch)    cmd_switch "$@" ;;
        help|--help|-h) cmd_help ;;
        *)
            log_error "未知命令: $cmd"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
