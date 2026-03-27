#!/usr/bin/env bash
# scheduler_macos.sh — macOS launchd 调度器

LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PEAK_PLIST_NAME="com.claude.scheduler.peak"
OFFPEAK_PLIST_NAME="com.claude.scheduler.offpeak"
PEAK_PLIST="${LAUNCH_AGENTS_DIR}/${PEAK_PLIST_NAME}.plist"
OFFPEAK_PLIST="${LAUNCH_AGENTS_DIR}/${OFFPEAK_PLIST_NAME}.plist"

# 生成 plist 文件内容
# 参数: label, program, args, hour, minute, log_file
_generate_plist() {
    local label="$1" program="$2" hour="$3" minute="$4" log_file="$5"

    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${program}</string>
        <string>switch</string>
        <string>${label##*.}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${log_file}</string>
    <key>StandardErrorPath</key>
    <string>${log_file}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>TRIGGER</key>
        <string>scheduled</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
EOF
}

scheduler_install() {
    config_load
    local log_dir="${CLAUDE_DIR}/logs"
    mkdir -p "$log_dir"

    # 解析时间
    local peak_hour peak_min offpeak_hour offpeak_min
    peak_hour="${PEAK_START%%:*}"
    peak_min="${PEAK_START#*:}"
    offpeak_hour="${OFFPEAK_START%%:*}"
    offpeak_min="${OFFPEAK_START#*:}"

    # 获取脚本绝对路径
    local main_script="${SCRIPT_DIR}/claude-model-scheduler.sh"
    if [[ ! -f "$main_script" ]]; then
        main_script="$(cd "${SCRIPT_DIR}/.." && pwd)/claude-model-scheduler.sh"
    fi

    # 生成并安装高峰期 plist
    log_step "安装高峰期调度任务 (${PEAK_START} → ${PEAK_MODEL})..."
    _generate_plist "$PEAK_PLIST_NAME" "$main_script" "$peak_hour" "$peak_min" "${log_dir}/peak-switch.log" > "$PEAK_PLIST"
    launchctl bootout "gui/$(id -u)/${PEAK_PLIST_NAME}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PEAK_PLIST"
    log_info "已加载 ${PEAK_PLIST_NAME}"

    # 生成并安装非高峰期 plist
    log_step "安装非高峰期调度任务 (${OFFPEAK_START} → ${OFFPEAK_MODEL})..."
    _generate_plist "$OFFPEAK_PLIST_NAME" "$main_script" "$offpeak_hour" "$offpeak_min" "${log_dir}/offpeak-switch.log" > "$OFFPEAK_PLIST"
    launchctl bootout "gui/$(id -u)/${OFFPEAK_PLIST_NAME}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$OFFPEAK_PLIST"
    log_info "已加载 ${OFFPEAK_PLIST_NAME}"
}

scheduler_uninstall() {
    for label_name in "$PEAK_PLIST_NAME" "$OFFPEAK_PLIST_NAME"; do
        local plist="${LAUNCH_AGENTS_DIR}/${label_name}.plist"
        if [[ -f "$plist" ]]; then
            launchctl bootout "gui/$(id -u)/${label_name}" 2>/dev/null || true
            rm -f "$plist"
            log_info "已卸载 ${label_name}"
        fi
    done
}

scheduler_status() {
    print_color "${_C_BOLD}调度任务状态（launchd）：${_C_RESET}\n"

    local found_any=false
    for label_name in "$PEAK_PLIST_NAME" "$OFFPEAK_PLIST_NAME"; do
        local plist="${LAUNCH_AGENTS_DIR}/${label_name}.plist"
        if [[ -f "$plist" ]]; then
            found_any=true
            local status
            if launchctl print "gui/$(id -u)/${label_name}" &>/dev/null; then
                status="${_C_GREEN}运行中${_C_RESET}"
            else
                status="${_C_YELLOW}已安装但未运行${_C_RESET}"
            fi

            local sched_time
            sched_time="$(jq -r '.StartCalendarInterval | "\(.Hour // "?"):\(.Minute // "?")"' "$plist" 2>/dev/null || echo "?")"
            local target_model="${label_name##*.}"

            printf "  ${_C_CYAN}%-30s${_C_RESET} %s → %s @ %s\n" "$label_name" "$status" "$target_model" "$sched_time"
        else
            printf "  ${_C_DIM}%-30s${_C_RESET} %s\n" "$label_name" "未安装"
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        log_warn "未找到调度任务"
    fi
}
