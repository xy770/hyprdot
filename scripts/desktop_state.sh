#!/bin/bash
# Hyprland Desktop State Manager
# 用于管理免打扰、消息折叠等桌面状态

STATE_FILE="$HOME/.config/hypr/desktop_state.json"
LOG_FILE="/tmp/desktop_state.log"

# 初始化状态文件（如果不存在）
init_state_file() {
    if [[ ! -f "$STATE_FILE" ]]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        cat > "$STATE_FILE" << EOF
{
  "do_not_disturb": false,
  "fold_qq_messages": false,
  "mute_all_notifications": false,
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "notification_rules": {
    "qq": {
      "enabled": true,
      "fold_content": false,
      "mute": false,
      "urgency": "normal"
    }
  }
}
EOF
        echo "[$(date)] Created initial state file" >> "$LOG_FILE"
    fi
}

# 读取状态值
get_state_value() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        jq -r ".$key" "$STATE_FILE" 2>/dev/null || echo "false"
    else
        echo "false"
    fi
}

# 读取嵌套状态值
get_nested_state_value() {
    local path="$1"
    if [[ -f "$STATE_FILE" ]]; then
        jq -r ".$path" "$STATE_FILE" 2>/dev/null || echo "false"
    else
        echo "false"
    fi
}

# 设置状态值
set_state_value() {
    local key="$1"
    local value="$2"

    if [[ -f "$STATE_FILE" ]]; then
        jq --arg key "$key" --arg value "$value" \
           '.[$key] = ($value | test("true") // ($value | test("false")) | if . then $value == "true" else $value end)' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

        # 更新最后修改时间
        jq --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.last_updated = $time' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

        echo "[$(date)] Set $key = $value" >> "$LOG_FILE"
    fi
}

# 切换免打扰模式
toggle_do_not_disturb() {
    current=$(get_state_value "do_not_disturb")
    new_value="false"
    [[ "$current" == "false" ]] && new_value="true"

    set_state_value "do_not_disturb" "$new_value"
    echo "免打扰模式: $new_value"

    # 应用到dunst
    apply_dunst_settings
}

# 切换QQ消息折叠
toggle_fold_qq_messages() {
    current=$(get_state_value "fold_qq_messages")
    new_value="false"
    [[ "$current" == "false" ]] && new_value="true"

    set_state_value "fold_qq_messages" "$new_value"
    echo "QQ消息折叠: $new_value"

    # 应用到dunst
    apply_dunst_settings
}

# 切换全局静音
toggle_mute_all() {
    current=$(get_state_value "mute_all_notifications")
    new_value="false"
    [[ "$current" == "false" ]] && new_value="true"

    set_state_value "mute_all_notifications" "$new_value"
    echo "全局静音: $new_value"

    # 应用到dunst
    apply_dunst_settings
}

# 应用设置到dunst
apply_dunst_settings() {
    do_not_disturb=$(get_state_value "do_not_disturb")
    fold_qq_messages=$(get_state_value "fold_qq_messages")
    mute_all=$(get_state_value "mute_all_notifications")

    # 重启dunst或发送信号
    if [[ "$do_not_disturb" == "true" ]] || [[ "$mute_all" == "true" ]]; then
        # 完全静音
        dunstctl set-paused true
        echo "[$(date)] Dunst paused (do_not_disturb=$do_not_disturb, mute_all=$mute_all)" >> "$LOG_FILE"
    else
        dunstctl set-paused false
        echo "[$(date)] Dunst resumed" >> "$LOG_FILE"
    fi

    # 重新加载配置（如果需要）
    pkill -USR1 dunst
}

# 检查自动规则
check_auto_rules() {
    current_time=$(date +"%H:%M")

    # 检查工作时间规则
    work_enabled=$(get_nested_state_value "auto_rules.work_hours.enabled")
    if [[ "$work_enabled" == "true" ]]; then
        work_start=$(get_nested_state_value "auto_rules.work_hours.start_time")
        work_end=$(get_nested_state_value "auto_rules.work_hours.end_time")

        if [[ "$current_time" > "$work_start" && "$current_time" < "$work_end" ]]; then
            # 应用工作时间规则
            fold_qq=$(get_nested_state_value "auto_rules.work_hours.rules.fold_qq_messages")
            set_state_value "fold_qq_messages" "$fold_qq"
        fi
    fi

    # 检查夜间模式规则
    night_enabled=$(get_nested_state_value "auto_rules.night_mode.enabled")
    if [[ "$night_enabled" == "true" ]]; then
        night_start=$(get_nested_state_value "auto_rules.night_mode.start_time")
        night_end=$(get_nested_state_value "auto_rules.night_mode.end_time")

        if [[ "$current_time" > "$night_start" || "$current_time" < "$night_end" ]]; then
            # 应用夜间模式规则
            set_state_value "do_not_disturb" "true"
            set_state_value "mute_all_notifications" "true"
            set_state_value "fold_qq_messages" "true"
        else
            # 检查是否需要退出夜间模式
            current_dnd=$(get_state_value "do_not_disturb")
            if [[ "$current_dnd" == "true" ]]; then
                set_state_value "do_not_disturb" "false"
                set_state_value "mute_all_notifications" "false"
            fi
        fi
    fi

    apply_dunst_settings
}

# 显示当前状态
show_status() {
    echo "=== Hyprland Desktop State ==="
    echo "免打扰模式: $(get_state_value "do_not_disturb")"
    echo "QQ消息折叠: $(get_state_value "fold_qq_messages")"
    echo "全局静音: $(get_state_value "mute_all_notifications")"
    echo "最后更新: $(get_state_value "last_updated")"
    echo "============================="
}

# 主函数
main() {
    init_state_file

    case "$1" in
        "toggle-dnd")
            toggle_do_not_disturb
            ;;
        "toggle-fold-qq")
            toggle_fold_qq_messages
            ;;
        "toggle-mute")
            toggle_mute_all
            ;;
        "status")
            show_status
            ;;
        "check-auto")
            check_auto_rules
            ;;
        "apply")
            apply_dunst_settings
            ;;
        *)
            echo "Usage: $0 [toggle-dnd|toggle-fold-qq|toggle-mute|status|check-auto|apply]"
            ;;
    esac
}

main "$@"
