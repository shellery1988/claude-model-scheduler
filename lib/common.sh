#!/usr/bin/env bash
# common.sh — 通用函数库：日志、颜色、JSON操作、平台检测、用户输入

# ── 路径常量 ──────────────────────────────────────────────
CLAUDE_DIR="${HOME}/.claude"
CLAUDE_SETTINGS="${CLAUDE_DIR}/settings.json"
SCHEDULER_CONFIG_DIR="${CLAUDE_DIR}/scheduler.d"
SCHEDULER_CONFIG="${SCHEDULER_CONFIG_DIR}/config.json"
SCHEDULER_HISTORY="${SCHEDULER_CONFIG_DIR}/history.log"
SCHEDULER_BACKUP_DIR="${CLAUDE_DIR}/backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 平台检测 ──────────────────────────────────────────────
detect_os() {
    local uname_out
    uname_out="$(uname -s)"
    case "${uname_out}" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

CURRENT_OS="$(detect_os)"

# ── 颜色支持检测 ──────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    _COLOR_ENABLED=1
else
    _COLOR_ENABLED=0
fi

# 颜色代码
_C_RED='\033[0;31m'
_C_GREEN='\033[0;32m'
_C_YELLOW='\033[0;33m'
_C_BLUE='\033[0;34m'
_C_CYAN='\033[0;36m'
_C_BOLD='\033[1m'
_C_DIM='\033[2m'
_C_RESET='\033[0m'

# ── 日志函数 ──────────────────────────────────────────────
_log() {
    local level="$1"; shift
    local color="$1"; shift
    if [[ $_COLOR_ENABLED -eq 1 ]]; then
        printf "${color}[%s]${_C_RESET} %s\n" "$level" "$*"
    else
        printf "[%s] %s\n" "$level" "$*"
    fi
}

log_info()  { _log "INFO"  "$_C_GREEN"  "$@"; }
log_warn()  { _log "WARN"  "$_C_YELLOW" "$@"; }
log_error() { _log "ERROR" "$_C_RED"    "$@"; }
log_step()  { _log "STEP"  "$_C_CYAN"   "$@"; }

# 带颜色的输出（非日志格式）
print_color() {
    if [[ $_COLOR_ENABLED -eq 1 ]]; then
        printf "%b" "$*"
    else
        # 去除 ANSI 转义码
        printf "%s" "$*" | sed 's/\x1b\[[0-9;]*m//g'
    fi
}

# ── JSON 操作 ─────────────────────────────────────────────
_json_cmd() {
    if command -v jq &>/dev/null; then
        echo "jq"
    elif command -v python3 &>/dev/null; then
        echo "python3"
    else
        echo ""
    fi
}

JSON_CMD="$(_json_cmd)"

# json_get_field <file> <field>
# 返回 JSON 文件中指定字段的值
json_get_field() {
    local file="$1" field="$2"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    case "$JSON_CMD" in
        jq)
            jq -r ".$field // empty" "$file"
            ;;
        python3)
            python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
keys = '$field'.lstrip('.').split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(1)
print(val if val is not None else '', end='')
" 2>/dev/null
            ;;
        *)
            log_error "需要 jq 或 python3 来处理 JSON"
            return 1
            ;;
    esac
}

# json_set_field <file> <field> <value>
# 原子写入：先写临时文件再 mv
json_set_field() {
    local file="$1" field="$2" value="$3"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    local tmpfile
    tmpfile="$(mktemp "${file}.XXXXXX")"
    case "$JSON_CMD" in
        jq)
            jq ".$field = $value" "$file" > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
            ;;
        python3)
            python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
keys = '$field'.lstrip('.').split('.')
obj = data
for k in keys[:-1]:
    obj = obj.setdefault(k, {})
obj[keys[-1]] = $value
with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null || { rm -f "$tmpfile"; return 1; }
            ;;
        *)
            rm -f "$tmpfile"
            log_error "需要 jq 或 python3 来处理 JSON"
            return 1
            ;;
    esac
    mv "$tmpfile" "$file"
}

# ── 用户输入辅助 ──────────────────────────────────────────
# 当 stdin 被管道占用时（如 curl | bash），从 /dev/tty 读取终端输入
if [[ -t 0 ]]; then
    _INPUT_FD="/dev/stdin"
else
    _INPUT_FD="/dev/tty"
    if [[ ! -e /dev/tty ]]; then
        log_error "无法访问终端，请在交互式终端中运行"
        exit 1
    fi
fi
# ask_choice <prompt> <option1> [option2] ...
# 结果通过全局变量 _ASK_RESULT 返回，避免 $(...) 子 shell 问题
# 选项超过 8 个时自动切换为多列布局
ask_choice() {
    local prompt="$1"; shift
    local options=("$@")
    local num=${#options[@]}
    local choice

    _ASK_RESULT=""
    while true; do
        print_color "${_C_BOLD}${prompt}${_C_RESET}\n"
        local i=1
        if (( num > 8 )); then
            # 多列布局：4 列
            local cols=4
            local rows=$(( (num + cols - 1) / cols ))
            local row col idx
            for (( row = 0; row < rows; row++ )); do
                for (( col = 0; col < cols; col++ )); do
                    idx=$(( row + col * rows ))
                    if (( idx < num )); then
                        printf "  ${_C_CYAN}%2d)${_C_RESET} %-6s" "$((idx+1))" "${options[idx]}"
                    fi
                done
                printf "\n"
            done
        else
            # 单列布局
            for opt in "${options[@]}"; do
                printf "  ${_C_CYAN}%d)${_C_RESET} %s\n" "$i" "$opt"
                ((i++))
            done
        fi
        printf "  ${_C_DIM}(输入编号或名称)${_C_RESET}: "
        read -r choice < "$_INPUT_FD"
        # 支持数字输入
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= num)); then
            _ASK_RESULT="${options[$((choice-1))]}"
            return 0
        fi
        # 支持直接输入选项名称（不区分大小写）
        local lower_choice
        lower_choice="$(echo "$choice" | tr '[:upper:]' '[:lower:]')"
        for opt in "${options[@]}"; do
            local lower_opt
            lower_opt="$(echo "$opt" | tr '[:upper:]' '[:lower:]')"
            if [[ "$lower_choice" == "$lower_opt" ]]; then
                _ASK_RESULT="$opt"
                return 0
            fi
        done
        log_warn "无效选择，请输入编号（1-${num:-?}）或选项名称"
    done
}

# ask_confirm <prompt> [default]
# default: y 或 n，默认 y
ask_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn_str

    if [[ "$default" == "y" ]]; then
        yn_str="[Y/n]"
    else
        yn_str="[y/N]"
    fi

    local answer
    printf "%s %s: " "$prompt" "$yn_str"
    read -r answer < "$_INPUT_FD"
    answer="${answer:-$default}"

    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ask_time <prompt> [default]
# 返回 HH:MM 格式的时间字符串
ask_time() {
    local prompt="$1"
    local default="${2:-}"
    local time_input

    while true; do
        if [[ -n "$default" ]]; then
            printf "%s (默认 %s): " "$prompt" "$default"
        else
            printf "%s: " "$prompt"
        fi
        read -r time_input < "$_INPUT_FD"
        time_input="${time_input:-$default}"

        # 校验 HH:MM 格式
        if [[ "$time_input" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
            echo "$time_input"
            return 0
        fi
        log_warn "时间格式无效，请使用 HH:MM（24小时制，如 09:30、18:00）"
    done
}

# ── 模型名映射 ────────────────────────────────────────────
# 将简写映射为完整的模型标识
resolve_model_name() {
    case "$1" in
        opus)   echo "opus" ;;
        sonnet) echo "sonnet" ;;
        haiku)  echo "haiku" ;;
        *) echo "$1" ;;
    esac
}

# 获取模型在 settings.json 中的环境变量字段名
get_model_env_key() {
    case "$1" in
        opus)   echo "ANTHROPIC_DEFAULT_OPUS_MODEL" ;;
        sonnet) echo "ANTHROPIC_DEFAULT_SONNET_MODEL" ;;
        haiku)  echo "ANTHROPIC_DEFAULT_HAIKU_MODEL" ;;
        *) log_error "未知模型: $1"; return 1 ;;
    esac
}
