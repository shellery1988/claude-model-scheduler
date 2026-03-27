#!/usr/bin/env bash
# scheduler_linux.sh — Linux cron 调度器

CRON_TAG="# claude-model-scheduler"

# 获取当前用户的 crontab
_get_crontab() {
    crontab -l 2>/dev/null || true
}

# 过滤掉调度器相关的 cron 条目
_filter_crontab() {
    grep -v "$CRON_TAG" || true
}

# 生成 cron 条目
# 参数: hour, minute, model
_make_cron_entry() {
    local hour="$1" minute="$2" model="$3"
    local main_script
    main_script="${SCRIPT_DIR}/claude-model-scheduler.sh"
    if [[ ! -f "$main_script" ]]; then
        main_script="$(cd "${SCRIPT_DIR}/.." && pwd)/claude-model-scheduler.sh"
    fi
    echo "${minute} ${hour} * * * TRIGGER=scheduled ${main_script} switch ${model} ${CRON_TAG}"
}

scheduler_install() {
    config_load

    # 解析时间
    local peak_hour peak_min offpeak_hour offpeak_min
    peak_hour="${PEAK_START%%:*}"
    peak_min="${PEAK_START#*:}"
    offpeak_hour="${OFFPEAK_START%%:*}"
    offpeak_min="${OFFPEAK_START#*:}"

    # 构建新的 crontab
    local current_crontab new_entries
    current_crontab="$(_get_crontab | _filter_crontab)"
    new_entries="$(_make_cron_entry "$peak_hour" "$peak_min" "$PEAK_MODEL")"
    new_entries+="\n$(_make_cron_entry "$offpeak_hour" "$offpeak_min" "$OFFPEAK_MODEL")"

    # 写入 crontab
    printf "%s\n%s\n" "$current_crontab" "$new_entries" | crontab -
    log_info "cron 任务已安装"
    log_step "高峰期:   ${PEAK_START} → ${PEAK_MODEL}"
    log_step "非高峰期: ${OFFPEAK_START} → ${OFFPEAK_MODEL}"
}

scheduler_uninstall() {
    local current_crontab
    current_crontab="$(_get_crontab | _filter_crontab)"

    if [[ -n "$current_crontab" ]]; then
        printf "%s\n" "$current_crontab" | crontab -
        log_info "cron 任务已移除"
    else
        # 清空 crontab
        crontab -r 2>/dev/null || true
        log_info "cron 任务已移除"
    fi
}

scheduler_status() {
    print_color "${_C_BOLD}调度任务状态（cron）：${_C_RESET}\n"

    local entries
    entries="$(_get_crontab | grep "$CRON_TAG" || true)"

    if [[ -z "$entries" ]]; then
        log_warn "未找到 cron 调度任务"
        return 0
    fi

    echo "$entries" | while IFS= read -r line; do
        local minute hour model
        minute="$(echo "$line" | awk '{print $1}')"
        hour="$(echo "$line" | awk '{print $2}')"
        model="$(echo "$line" | awk '{print $NF}')"
        printf "  ${_C_GREEN}✓${_C_RESET} ${_C_CYAN}%s:%s${_C_RESET} 每天切换到 ${_C_BOLD}%s${_C_RESET}\n" "$hour" "$minute" "$model"
    done
}
