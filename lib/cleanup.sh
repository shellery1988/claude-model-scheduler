#!/usr/bin/env bash
# cleanup.sh — 清理旧版实现

cleanup_legacy() {
    local cleaned=false

    # 检查旧版切换脚本
    local legacy_script="${CLAUDE_DIR}/scripts/switch-model.sh"
    if [[ -f "$legacy_script" ]]; then
        log_warn "检测到旧版切换脚本: ${legacy_script}"
        if ask_confirm "是否删除旧版切换脚本？"; then
            rm -f "$legacy_script"
            log_info "已删除旧版切换脚本"
            cleaned=true
        fi
    fi

    # 检查旧版 launchd plist（macOS）
    if [[ "$CURRENT_OS" == "macos" ]]; then
        local old_plists=(
            "com.claude.model.peak"
            "com.claude.model.offpeak"
        )
        for plist_name in "${old_plists[@]}"; do
            local plist="${HOME}/Library/LaunchAgents/${plist_name}.plist"
            if [[ -f "$plist" ]]; then
                log_warn "检测到旧版 plist: ${plist_name}.plist"
                if ask_confirm "是否卸载旧版调度任务 ${plist_name}？"; then
                    launchctl bootout "gui/$(id -u)/${plist_name}" 2>/dev/null || true
                    rm -f "$plist"
                    log_info "已卸载旧版调度任务 ${plist_name}"
                    cleaned=true
                fi
            fi
        done
    fi

    if [[ "$cleaned" == "true" ]]; then
        echo ""
        log_info "旧版清理完成"
    fi
}
