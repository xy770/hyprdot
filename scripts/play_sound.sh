#!/bin/bash
# 智能通知声音脚本 - 多重进度检测

# 设置环境变量
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"

# 通过环境变量获取通知信息
urgency="${DUNST_URGENCY:-}"
category="${DUNST_CATEGORY:-}"
hints="${DUNST_HINTS:-}"
app_name="${DUNST_APP_NAME:-}"
summary="${DUNST_SUMMARY:-}"
body="${DUNST_BODY:-}"

# 记录调试信息
echo "[$(date)] Script triggered via environment variables" >> /tmp/dunst.log
echo "  DUNST_URGENCY: $urgency" >> /tmp/dunst.log
echo "  DUNST_CATEGORY: $category" >> /tmp/dunst.log
echo "  DUNST_HINTS: $hints" >> /tmp/dunst.log
echo "  DUNST_APP_NAME: $app_name" >> /tmp/dunst.log
echo "  DUNST_SUMMARY: $summary" >> /tmp/dunst.log
echo "  DUNST_BODY: $body" >> /tmp/dunst.log
echo "  Args: $*" >> /tmp/dunst.log
echo "---" >> /tmp/dunst.log

# 1. 低紧急度不播放声音
if [[ "$urgency" == "LOW" ]]; then
    echo "[$(date)] Skipped: LOW urgency" >> /tmp/dunst.log
    exit 0
fi

# 2. 检查是否包含进度条 - 多重检测方式
is_progress=false

# 2.1 检查hints中的value字段
if [[ "$hints" == *"value"* ]]; then
    is_progress=true
    echo "[$(date)] Detected progress via hints: $hints" >> /tmp/dunst.log
fi

# 2.2 检查消息内容是否包含进度关键词
if [[ "$body" == *"进度"* ]] || [[ "$body" == *"%"* ]] || [[ "$body" == *"% "* ]] || [[ "$summary" == *"进度"* ]]; then
    # 但要排除一些特殊情况（如时间中的%）
    if ! [[ "$body" == *"100%"* && "$body" == *"完成"* ]]; then
        is_progress=true
        echo "[$(date)] Detected progress via content: $body" >> /tmp/dunst.log
    fi
fi

# 2.3 检查类别
case "${category,,}" in
    *progress*|*transfer*|*download*|*upload*|*x-dunst.progress*)
        is_progress=true
        echo "[$(date)] Detected progress via category: $category" >> /tmp/dunst.log
        ;;
esac

# 2.4 检查应用名称（某些应用专门发送进度通知）
case "${app_name,,}" in
    *transfer*|*download*|*upload*|*sync*|*backup*)
        is_progress=true
        echo "[$(date)] Detected progress via app name: $app_name" >> /tmp/dunst.log
        ;;
esac

# 3. 如果是进度通知，跳过声音
if [[ "$is_progress" == "true" ]]; then
    echo "[$(date)] Skipped: Progress notification detected" >> /tmp/dunst.log
    exit 0
fi

# 4. 播放声音
SOUND_FILE="$HOME/.config/hypr/sounds/notify.ogg"
if [[ -f "$SOUND_FILE" ]]; then
    echo "[$(date)] Playing sound: $SOUND_FILE" >> /tmp/dunst.log
    paplay "$SOUND_FILE" --volume=65536 > /dev/null 2>&1 &
else
    echo "[$(date)] ERROR: Sound file not found" >> /tmp/dunst.log
fi

exit 0
