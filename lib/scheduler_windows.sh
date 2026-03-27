#!/usr/bin/env bash
# scheduler_windows.sh — Windows schtasks 调度器（Git Bash）

PEAK_TASK_NAME="ClaudeModelSchedulerPeak"
OFFPEAK_TASK_NAME="ClaudeModelSchedulerOffPeak"

scheduler_install() {
    config_load

    # 获取脚本路径（转换为 Windows 路径）
    local main_script
    main_script="${SCRIPT_DIR}/claude-model-scheduler.sh"
    if [[ ! -f "$main_script" ]]; then
        main_script="$(cd "${SCRIPT_DIR}/.." && pwd)/claude-model-scheduler.sh"
    fi
    local win_script
    win_script="$(cygpath -w "$main_script")"

    # 解析时间
    local peak_hour peak_min offpeak_hour offpeak_min
    peak_hour="${PEAK_START%%:*}"
    peak_min="${PEAK_START#*:}"
    offpeak_hour="${OFFPEAK_START%%:*}"
    offpeak_min="${OFFPEAK_START#*:}"

    # 删除已有任务（忽略错误）
    schtasks //Delete //TN "$PEAK_TASK_NAME" //F &>/dev/null || true
    schtasks //Delete //TN "$OFFPEAK_TASK_NAME" //F &>/dev/null || true

    # 创建高峰期任务
    log_step "安装高峰期调度任务 (${PEAK_START} → ${PEAK_MODEL})..."
    schtasks //Create \
        //TN "$PEAK_TASK_NAME" \
        //TR "set TRIGGER=scheduled && bash \"${win_script}\" switch ${PEAK_MODEL}" \
        //SC DAILY \
        //ST "${peak_hour}:${peak_min}" \
        //RL HIGHEST \
        //F \
        &>/dev/null
    log_info "已创建任务 ${PEAK_TASK_NAME}"

    # 创建非高峰期任务
    log_step "安装非高峰期调度任务 (${OFFPEAK_START} → ${OFFPEAK_MODEL})..."
    schtasks //Create \
        //TN "$OFFPEAK_TASK_NAME" \
        //TR "set TRIGGER=scheduled && bash \"${win_script}\" switch ${OFFPEAK_MODEL}" \
        //SC DAILY \
        //ST "${offpeak_hour}:${offpeak_min}" \
        //RL HIGHEST \
        //F \
        &>/dev/null
    log_info "已创建任务 ${OFFPEAK_TASK_NAME}"
}

scheduler_uninstall() {
    for task_name in "$PEAK_TASK_NAME" "$OFFPEAK_TASK_NAME"; do
        if schtasks //Query //TN "$task_name" &>/dev/null; then
            schtasks //Delete //TN "$task_name" //F &>/dev/null
            log_info "已删除任务 ${task_name}"
        fi
    done
}

scheduler_status() {
    print_color "${_C_BOLD}调度任务状态（schtasks）：${_C_RESET}\n"

    local found_any=false
    for task_name in "$PEAK_TASK_NAME" "$OFFPEAK_TASK_NAME"; do
        if schtasks //Query //TN "$task_name" &>/dev/null; then
            found_any=true
            local info
            info="$(schtasks //Query //TN "$task_name" //FO LIST 2>/dev/null)"
            local status_line next_run
            status_line="$(echo "$info" | grep -i "状态:" || echo "")"
            next_run="$(echo "$info" | grep -i "下次运行时间:" || echo "")"

            if echo "$status_line" | grep -qi "已启用\|Enabled\|Ready"; then
                status_line="${_C_GREEN}已启用${_C_RESET}"
            else
                status_line="${_C_YELLOW}${status_line}${_C_RESET}"
            fi

            printf "  ${_C_CYAN}%-35s${_C_RESET} %s" "$task_name" "$status_line"
            if [[ -n "$next_run" ]]; then
                printf "  %s" "$next_run"
            fi
            printf "\n"
        else
            printf "  ${_C_DIM}%-35s${_C_RESET} 未安装\n" "$task_name"
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        log_warn "未找到调度任务"
    fi
}
