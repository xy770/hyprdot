#!/bin/bash
# screenshot.sh — Hyprland 截图（live / freeze）

MODE="live"

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode) MODE="$2"; shift 2 ;;
        *) echo "未知选项: $1" >&2; echo "用法: $0 [-m|--mode live|freeze]" >&2; exit 1 ;;
    esac
done

if [[ "$MODE" != "live" && "$MODE" != "freeze" ]]; then
    echo "错误：模式必须是 'live' 或 'freeze'" >&2
    exit 1
fi

need() {
    for c in "$@"; do
        command -v "$c" &>/dev/null || {
            notify-send --urgency=critical "依赖缺失" "缺少命令: $c"
            exit 1
        }
    done
}

kill_interfering_menus() {
    for app in fuzzel rofi wofi; do
        pkill -x "$app" 2>/dev/null
    done
}

# ---------- live ----------
run_live_mode() {
    need notify-send slurp grim wl-copy
    kill_interfering_menus

    # 核心提速1：使用内存盘，极速读写
    local TEMP_FILE="/dev/shm/screenshot-$$.png"

    local GEOM
    GEOM=$(slurp -d -c "#b072d1" -s "#40000000" -w 3)

    if [ -z "$GEOM" ]; then
        notify-send --urgency=low --icon="camera-photo" --expire-time=1500 "截图已取消" "未选择任何区域"
        return 0
    fi

    if ! grim -g "$GEOM" "$TEMP_FILE"; then
        notify-send --urgency=critical "截图失败" "无法捕获图像"
        return 1
    fi

    if ! wl-copy --type image/png < "$TEMP_FILE"; then
        notify-send --urgency=critical "截图失败" "无法复制到剪贴板"
        rm -f "$TEMP_FILE"
        return 1
    fi

    command -v cliphist &>/dev/null && cliphist add -t image/png < "$TEMP_FILE" 2>/dev/null || true

    local SIZE=$(identify -format '%wx%h' "$TEMP_FILE" 2>/dev/null || echo "未知")
    notify-send -i "$TEMP_FILE" --expire-time=2500 -a "screenshot" "选区截图已复制" "尺寸: $SIZE"
    
    ( sleep 5; rm -f "$TEMP_FILE" ) &
}

# ---------- freeze ----------
run_freeze_mode() {
    need notify-send slurp grim wl-copy imv jq hyprctl identify awk convert

    # 使用内存盘，保留无损 PNG 格式
    local FULL_SCREEN="/dev/shm/frozen-$$.png"
    local CROPPED_FILE="/dev/shm/cropped-$$.png"

    local MONITOR_INFO OUTPUT SCALE
    MONITOR_INFO=$(hyprctl monitors -j 2>/dev/null | jq -r 'map(select(.focused))[0] // .[0]')
    OUTPUT=$(jq -r '.name // empty' <<< "$MONITOR_INFO")
    SCALE=$(jq -r '.scale // 1' <<< "$MONITOR_INFO")

    if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "null" ]; then
        notify-send --urgency=critical "失败" "无法获取显示器信息"
        return 1
    fi

    # 无损抓取全屏
    if ! grim -o "$OUTPUT" "$FULL_SCREEN"; then
        notify-send --urgency=critical "失败" "无法捕获屏幕"
        return 1
    fi

    kill_interfering_menus

    local IMG_W IMG_H
    read -r IMG_W IMG_H < <(identify -format '%w %h' "$FULL_SCREEN" 2>/dev/null)
    [ -z "$IMG_W" ] && IMG_W=0; [ -z "$IMG_H" ] && IMG_H=0

    # 启动 imv，由于规则优化，瞬间全屏
    imv -n "screenshot-preview" -f "$FULL_SCREEN" &
    local IMV_PID=$!

    # 极速寻找窗口地址
    local ADDR="" i
    for i in {1..100}; do
        ADDR=$(hyprctl clients -j 2>/dev/null | jq -r --arg pid "$IMV_PID" '.[] | select(.pid == ($pid|tonumber)) | .address' | head -n1)
        [ -n "$ADDR" ] && [ "$ADDR" != "null" ] && break
        sleep 0.01
    done

    # 极短的渲染等待，保证画面刷出
    sleep 0.05

    local GEOM
    GEOM=$(slurp -d -c "#b072d1" -s "#40000000" -w 3)

    # 清理预览器
    kill "$IMV_PID" 2>/dev/null
    wait "$IMV_PID" 2>/dev/null

    if [ -z "$GEOM" ]; then
        notify-send --urgency=low "已取消" "未选择区域"
        rm -f "$FULL_SCREEN"
        return 0
    fi

    # 解析逻辑坐标 (X,Y WxH)
    local XL="${GEOM%,*}"             # X
    local YWL="${GEOM#*,}"            # Y WxH
    local Y="${YWL%% *}"              # Y
    local WXH="${YWL#* }"             # WxH
    local W="${WXH%x*}"
    local H="${WXH#*x}"

    # 原生坐标转换 (scale=1.6 等情况下转为物理像素)
    local PHYS_X PHYS_Y PHYS_W PHYS_H
    read -r PHYS_X PHYS_Y PHYS_W PHYS_H < <(
        awk -v x="$XL" -v y="$Y" -v w="$W" -v h="$H" -v s="$SCALE" \
            'BEGIN { printf "%d %d %d %d\n", x*s+0.5, y*s+0.5, w*s+0.5, h*s+0.5 }'
    )

    # 边界保护
    (( PHYS_X < 0 )) && PHYS_X=0
    (( PHYS_Y < 0 )) && PHYS_Y=0
    if [ "$IMG_W" -gt 0 ]; then
        (( PHYS_X >= IMG_W )) && PHYS_X=$((IMG_W - 1))
        (( PHYS_X + PHYS_W > IMG_W )) && PHYS_W=$((IMG_W - PHYS_X))
    fi
    if [ "$IMG_H" -gt 0 ]; then
        (( PHYS_Y >= IMG_H )) && PHYS_Y=$((IMG_H - 1))
        (( PHYS_Y + PHYS_H > IMG_H )) && PHYS_H=$((IMG_H - PHYS_Y))
    fi
    (( PHYS_W < 1 )) && PHYS_W=1; (( PHYS_H < 1 )) && PHYS_H=1

    # 【核心提速2】无损极速裁剪
    # 直接从内存盘读取原图，裁剪后写回内存盘。使用 png 快速压缩级别以避免高CPU占用。
    if convert "$FULL_SCREEN" -crop "${PHYS_W}x${PHYS_H}+${PHYS_X}+${PHYS_Y}" +repage -define png:compression-level=1 "$CROPPED_FILE" 2>/dev/null; then
        if wl-copy --type image/png < "$CROPPED_FILE"; then
            command -v cliphist &>/dev/null && cliphist add -t image/png < "$CROPPED_FILE" 2>/dev/null || true
            local SIZE=$(identify -format '%wx%h' "$CROPPED_FILE" 2>/dev/null || echo "未知")
            notify-send -i "$CROPPED_FILE" -a "screenshot" "定格截图成功" "尺寸: $SIZE"
            ( sleep 5; rm -f "$CROPPED_FILE" ) &
        fi
    else
        notify-send --urgency=critical "裁剪失败" "无效选区"
    fi
    
    rm -f "$FULL_SCREEN"
}

case "$MODE" in
    live)   run_live_mode ;;
    freeze) run_freeze_mode ;;
esac
