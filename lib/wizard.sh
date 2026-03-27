#!/usr/bin/env bash
# wizard.sh — 交互式安装向导

wizard_run() {
    # 显示 Banner
    print_color "\n"
    print_color "${_C_CYAN}"
    cat <<'BANNER'
 ╔══════════════════════════════════════════╗
 ║     Claude Model Scheduler Setup         ║
 ║     模型定时切换器 · 安装向导             ║
 ╚══════════════════════════════════════════╝
BANNER
    print_color "${_C_RESET}\n"

    # 检测平台
    local os
    os="$(detect_os)"
    log_info "检测到操作系统: ${os}"
    echo ""

    # 检查并清理旧版
    source "${LIB_DIR}/cleanup.sh"
    cleanup_legacy

    # 检查是否已有配置
    if [[ -f "$SCHEDULER_CONFIG" ]]; then
        log_warn "检测到已有配置"
        show_config
        if ! ask_confirm "是否重新配置？"; then
            log_info "保持现有配置不变"
            return 0
        fi
    fi

    # 检查 settings.json
    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        log_error "未找到 Claude Code 配置文件: ${CLAUDE_SETTINGS}"
        log_error "请先安装并运行 Claude Code"
        exit 1
    fi

    # ── Step 1: 检测当前模型映射 ──
    print_color "${_C_BOLD}━━━ Step 1: 模型配置检测 ━━━${_C_RESET}\n"
    log_info "正在从 ${CLAUDE_SETTINGS} 读取当前模型配置..."
    echo ""

    local model_mappings=()
    local has_mappings=true

    for model in opus sonnet haiku; do
        local env_key val
        env_key="$(get_model_env_key "$model")"
        val="$(json_get_field "$CLAUDE_SETTINGS" "env.$env_key" || true)"
        if [[ -n "$val" ]]; then
            model_mappings+=("$model:$val")
            printf "  %-8s → %s\n" "$model" "$val"
        else
            printf "  %-8s → ${_C_DIM}(未设置)${_C_RESET}\n" "$model"
            has_mappings=false
        fi
    done
    echo ""

    if [[ "$has_mappings" == "false" ]]; then
        log_warn "部分模型未配置，切换功能可能受限"
        if ! ask_confirm "是否继续安装？"; then
            exit 0
        fi
    fi

    # ── Step 2: 选择高峰期模型 ──
    print_color "${_C_BOLD}━━━ Step 2: 高峰期模型 ━━━${_C_RESET}\n"
    local peak_model
    peak_model="$(ask_choice "选择高峰期使用的模型（白天工作时段）：" "sonnet" "opus" "haiku")"
    echo ""

    # ── Step 3: 选择非高峰期模型 ──
    print_color "${_C_BOLD}━━━ Step 3: 非高峰期模型 ━━━${_C_RESET}\n"
    local offpeak_model
    offpeak_model="$(ask_choice "选择非高峰期使用的模型（夜间/周末）：" "opus" "sonnet" "haiku")"
    echo ""

    if [[ "$peak_model" == "$offpeak_model" ]]; then
        log_warn "高峰期和非高峰期选择了相同模型，将不会产生实际切换效果"
        if ! ask_confirm "是否继续？"; then
            exit 0
        fi
    fi

    # ── Step 4: 设置切换时间 ──
    print_color "${_C_BOLD}━━━ Step 4: 切换时间设置 ━━━${_C_RESET}\n"
    print_color "${_C_DIM}请输入 24 小时制时间（HH:MM），直接回车可使用默认值${_C_RESET}\n"
    echo ""
    local peak_start offpeak_start

    if [[ -f "$SCHEDULER_CONFIG" ]]; then
        peak_start="$(json_get_field "$SCHEDULER_CONFIG" "peak_start" || true)"
        offpeak_start="$(json_get_field "$SCHEDULER_CONFIG" "offpeak_start" || true)"
    fi

    peak_start="$(ask_time "高峰期开始时间（切换到 ${peak_model}）" "${peak_start:-09:00}")"
    offpeak_start="$(ask_time "非高峰期开始时间（切换到 ${offpeak_model}）" "${offpeak_start:-18:00}")"
    echo ""

    # ── Step 5: 确认配置 ──
    print_color "${_C_BOLD}━━━ Step 5: 确认配置 ━━━${_C_RESET}\n"
    print_color "${_C_BOLD}配置摘要：${_C_RESET}\n"
    printf "  高峰期:     ${_C_CYAN}%s${_C_RESET} @ %s\n" "$peak_model" "$peak_start"
    printf "  非高峰期:   ${_C_CYAN}%s${_C_RESET} @ %s\n" "$offpeak_model" "$offpeak_start"
    printf "  操作系统:   %s\n" "$os"
    echo ""

    if ! ask_confirm "确认安装？"; then
        log_info "已取消安装"
        exit 0
    fi

    # ── Step 6: 保存配置并安装 ──
    print_color "${_C_BOLD}━━━ Step 6: 部署调度任务 ━━━${_C_RESET}\n"
    echo ""

    # 构建模型映射 JSON
    local models_json="{"
    local first=true
    for mapping in "${model_mappings[@]}"; do
        local mname="${mapping%%:*}"
        local mval="${mapping#*:}"
        if [[ "$first" == "true" ]]; then
            first=false
        else
            models_json+=","
        fi
        models_json+="\"${mname}\":\"${mval}\""
    done
    models_json+="}"

    # 写入配置
    config_ensure_dir
    local installed_at
    installed_at="$(date '+%Y-%m-%d %H:%M:%S')"
    cat > "$SCHEDULER_CONFIG" <<EOF
{
  "peak_model": "${peak_model}",
  "offpeak_model": "${offpeak_model}",
  "peak_start": "${peak_start}",
  "offpeak_start": "${offpeak_start}",
  "installed_at": "${installed_at}",
  "models": ${models_json}
}
EOF

    log_info "配置已保存到 ${SCHEDULER_CONFIG}"

    # 加载对应平台的调度器并安装
    case "$os" in
        macos)   source "${LIB_DIR}/scheduler_macos.sh"   ;;
        linux)   source "${LIB_DIR}/scheduler_linux.sh"   ;;
        windows) source "${LIB_DIR}/scheduler_windows.sh" ;;
        *)       log_error "不支持的操作系统: $os"; exit 1 ;;
    esac

    scheduler_install

    echo ""
    print_color "${_C_GREEN}${_C_BOLD}安装完成！${_C_RESET}\n"
    print_color "调度任务已部署，模型将在设定时间自动切换。\n"
    print_color "运行 ${_C_CYAN}./claude-model-scheduler.sh status${_C_RESET} 查看状态\n"
    echo ""
}
