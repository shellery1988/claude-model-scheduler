#!/usr/bin/env bash
# config.sh — 配置管理：读写 config.json、模型切换、历史记录

# ── 配置文件操作 ──────────────────────────────────────────

# 确保配置目录存在
config_ensure_dir() {
    mkdir -p "$SCHEDULER_CONFIG_DIR" "$SCHEDULER_BACKUP_DIR"
}

# 初始化默认配置
config_init() {
    config_ensure_dir
    if [[ ! -f "$SCHEDULER_CONFIG" ]]; then
        cat > "$SCHEDULER_CONFIG" <<EOF
{
  "peak_model": "sonnet",
  "offpeak_model": "opus",
  "peak_start": "09:00",
  "offpeak_start": "18:00",
  "installed_at": ""
}
EOF
    fi
}

# 加载配置到全局变量
config_load() {
    config_init
    PEAK_MODEL="$(json_get_field "$SCHEDULER_CONFIG" "peak_model" || true)"
    OFFPEAK_MODEL="$(json_get_field "$SCHEDULER_CONFIG" "offpeak_model" || true)"
    PEAK_START="$(json_get_field "$SCHEDULER_CONFIG" "peak_start" || true)"
    OFFPEAK_START="$(json_get_field "$SCHEDULER_CONFIG" "offpeak_start" || true)"
}

# 保存全局变量到配置文件
config_save() {
    config_ensure_dir
    local installed_at
    installed_at="$(json_get_field "$SCHEDULER_CONFIG" "installed_at" || true)"
    cat > "$SCHEDULER_CONFIG" <<EOF
{
  "peak_model": "${PEAK_MODEL:-sonnet}",
  "offpeak_model": "${OFFPEAK_MODEL:-opus}",
  "peak_start": "${PEAK_START:-09:00}",
  "offpeak_start": "${OFFPEAK_START:-18:00}",
  "installed_at": "${installed_at}"
}
EOF
}

# 设置单个配置项
config_set() {
    local key="$1" value="$2"
    case "$JSON_CMD" in
        jq)
            local tmpfile
            tmpfile="$(mktemp "${SCHEDULER_CONFIG}.XXXXXX")"
            jq ".$key = \"$value\"" "$SCHEDULER_CONFIG" > "$tmpfile" && mv "$tmpfile" "$SCHEDULER_CONFIG"
            ;;
        python3)
            python3 -c "
import json
with open('$SCHEDULER_CONFIG') as f:
    data = json.load(f)
data['$key'] = '$value'
with open('$SCHEDULER_CONFIG', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
            ;;
    esac
}

# ── 模型切换 ──────────────────────────────────────────────

# 执行模型切换
# 参数: model_name (opus/sonnet/haiku)
# 环境变量: TRIGGER=manual|scheduled
do_switch() {
    local model="$1"
    local trigger="${TRIGGER:-manual}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    model="$(resolve_model_name "$model")"

    # 获取当前 primaryModel
    local current_model
    current_model="$(json_get_field "$CLAUDE_SETTINGS" "primaryModel" || true)"

    # 如果已经是目标模型，跳过
    if [[ "$current_model" == "$model" ]]; then
        log_info "当前已是 ${model} 模型，无需切换"
        return 0
    fi

    # 备份当前配置
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        local backup_name="settings.json.$(date '+%Y%m%d_%H%M%S')"
        cp "$CLAUDE_SETTINGS" "${SCHEDULER_BACKUP_DIR}/${backup_name}"
        log_info "已备份当前配置到 ${SCHEDULER_BACKUP_DIR}/${backup_name}"
    fi

    # 执行切换：同时修改 model 和 primaryModel
    json_set_field "$CLAUDE_SETTINGS" "primaryModel" "\"$model\""
    json_set_field "$CLAUDE_SETTINGS" "model" "\"$model\""

    log_info "已从 ${current_model} 切换到 ${model} 模型 (${trigger})"
    history_record "$model" "$trigger" "$timestamp"
}

# ── 历史记录 ──────────────────────────────────────────────

# 记录切换历史
# 参数: model, trigger, timestamp
history_record() {
    local model="$1" trigger="$2" timestamp="$3"
    config_ensure_dir

    echo "${timestamp} | ${model} | ${trigger}" >> "$SCHEDULER_HISTORY"

    # 保留最近 200 条
    local count
    count="$(wc -l < "$SCHEDULER_HISTORY" 2>/dev/null || echo 0)"
    if (( count > 200 )); then
        tail -n 200 "$SCHEDULER_HISTORY" > "${SCHEDULER_HISTORY}.tmp"
        mv "${SCHEDULER_HISTORY}.tmp" "$SCHEDULER_HISTORY"
    fi
}

# 显示最近 N 条切换记录
# 参数: n (默认 10)
show_recent_history() {
    local n="${1:-10}"
    if [[ ! -f "$SCHEDULER_HISTORY" ]]; then
        log_info "暂无切换记录"
        return 0
    fi

    local total
    total="$(wc -l < "$SCHEDULER_HISTORY" | tr -d ' ')"
    if (( total == 0 )); then
        log_info "暂无切换记录"
        return 0
    fi

    print_color "${_C_BOLD}最近 ${n} 条切换记录（共 ${total} 条）：${_C_RESET}\n"
    printf "${_C_DIM}%-22s | %-10s | %-10s${_C_RESET}\n" "时间" "模型" "触发方式"
    printf "${_C_DIM}---------------------- | ---------- | ----------${_C_RESET}\n"
    tail -n "$n" "$SCHEDULER_HISTORY" | while IFS='|' read -r ts model trigger; do
        ts="$(echo "$ts" | xargs)"
        model="$(echo "$model" | xargs)"
        trigger="$(echo "$trigger" | xargs)"
        printf "%-22s | ${_C_CYAN}%-10s${_C_RESET} | %-10s\n" "$ts" "$model" "$trigger"
    done
}

# ── 显示当前配置 ──────────────────────────────────────────
show_config() {
    if [[ ! -f "$SCHEDULER_CONFIG" ]]; then
        log_warn "尚未配置，请先运行 install"
        return 0
    fi

    print_color "\n${_C_BOLD}当前配置：${_C_RESET}\n"
    printf "  高峰期模型:     ${_C_CYAN}%s${_C_RESET}\n" "$(json_get_field "$SCHEDULER_CONFIG" "peak_model" || true)"
    printf "  高峰期开始时间: ${_C_CYAN}%s${_C_RESET}\n" "$(json_get_field "$SCHEDULER_CONFIG" "peak_start" || true)"
    printf "  非高峰期模型:   ${_C_CYAN}%s${_C_RESET}\n" "$(json_get_field "$SCHEDULER_CONFIG" "offpeak_model" || true)"
    printf "  非高峰期开始时间: ${_C_CYAN}%s${_C_RESET}\n" "$(json_get_field "$SCHEDULER_CONFIG" "offpeak_start" || true)"
    printf "  安装时间:       ${_C_DIM}%s${_C_RESET}\n" "$(json_get_field "$SCHEDULER_CONFIG" "installed_at" || true)"

    # 显示模型映射
    local models_json
    models_json="$(json_get_field "$SCHEDULER_CONFIG" "models" || true)"
    if [[ -n "$models_json" ]]; then
        printf "\n${_C_BOLD}模型映射：${_C_RESET}\n"
        for model in opus sonnet haiku; do
            local val
            val="$(json_get_field "$SCHEDULER_CONFIG" "models.$model" || true)"
            if [[ -n "$val" ]]; then
                printf "  %-8s → %s\n" "$model" "$val"
            fi
        done
    fi
    echo ""
}
