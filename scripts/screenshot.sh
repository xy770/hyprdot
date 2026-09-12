#!/bin/bash

# 默认模式
MODE="live"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        *)
            echo "未知选项: $1" >&2
            echo "用法: $0 [-m|--mode live|freeze]" >&2
            exit 1
            ;;
    esac
done

# 验证模式
if [[ "$MODE" != "live" && "$MODE" != "freeze" ]]; then
    echo "错误：模式必须是 'live' 或 'freeze'" >&2
    exit 1
fi

# 图标定义
ICON_SUCCESS="camera-photo"
ICON_CANCEL="camera-photo"
ICON_ERROR="dialog-error"

# 检查必要工具
for cmd in notify-send wl-copy; do
    if ! command -v "$cmd" &>/dev/null; then
        notify-send --urgency=critical "依赖缺失" "缺少命令: $cmd"
        exit 1
    fi
done

# 函数：live 模式（原生）
run_live_mode() {
    TEMP_FILE="/tmp/screenshot-$(date +%s).png"
    GEOM=$(slurp -d -c "#b072d1" -s "#40000000" -w 3)

    if [ -z "$GEOM" ]; then
        notify-send \
            --urgency=low \
            --icon="$ICON_CANCEL" \
            --expire-time=1500 \
            "截图已取消" \
            "未选择任何区域"
        return 0
    fi

    if grim -g "$GEOM" - | tee "$TEMP_FILE" | wl-copy --type image/png; then
        if command -v cliphist &>/dev/null; then
            cliphist add < "$TEMP_FILE" 2>/dev/null || true
        fi
        SIZE=$(identify -format '%wx%h' "$TEMP_FILE" 2>/dev/null || echo "未知")
        notify-send \
            -i "$TEMP_FILE" \
            --expire-time=2500 \
            -a "screenshot" \
            "选区截图已复制" \
            "尺寸: $SIZE"
        rm -f "$TEMP_FILE"
        return 0
    else
        notify-send \
            --urgency=critical \
            --expire-time=4000 \
            "截图失败" \
            "无法捕获或复制图像"
        rm -f "$TEMP_FILE"
        return 1
    fi
}

# 函数：freeze 模式（定格画面）
run_freeze_mode() {
    # 检查依赖（添加 jq 用于解析 hyprctl 输出）
    for cmd in imv convert jq bc; do
        if ! command -v "$cmd" &>/dev/null; then
            notify-send --urgency=critical "依赖缺失" "需要: $cmd"
            exit 1
        fi
    done

    FULL_SCREEN="/tmp/frozen-$(date +%s).png"
    CROPPED_FILE="/tmp/cropped-$(date +%s).png"

    # 获取当前聚焦的显示器名称和缩放因子
    # 假设只有一个显示器，取第一个；若多显示器，可根据鼠标位置确定（见下文注释）
    MONITOR_INFO=$(hyprctl monitors -j | jq '.[0]')
    OUTPUT=$(echo "$MONITOR_INFO" | jq -r '.name')
    SCALE=$(echo "$MONITOR_INFO" | jq -r '.scale')
    echo "使用输出: $OUTPUT, 缩放因子: $SCALE"  # 可重定向到日志

    # 1. 捕获指定输出（确保图像为物理分辨率）
    if ! grim -o "$OUTPUT" "$FULL_SCREEN"; then
        notify-send --urgency=critical "失败" "无法捕获屏幕"
        rm -f "$FULL_SCREEN" 2>/dev/null
        return 1
    fi

    # 2. 启动 imv 全屏显示冻结图
    imv -f "$FULL_SCREEN" &
    IMV_PID=$!
    sleep 0.1

    # 3. 选区
    GEOM=$(slurp -d -c "#b072d1" -s "#40000000" -w 3)

    # 4. 关闭 imv
    kill "$IMV_PID" 2>/dev/null
    wait "$IMV_PID" 2>/dev/null

    if [ -z "$GEOM" ]; then
        rm -f "$FULL_SCREEN" "$CROPPED_FILE" 2>/dev/null
        notify-send --urgency=low "已取消" "未选择区域"
        return 0
    fi

    # 解析 slurp 输出: "X,Y WxH"
    IFS=', ' read -r X Y WxH <<< "$GEOM"
    W=${WxH%x*}
    H=${WxH#*x}

    # 将逻辑坐标转换为物理坐标（乘以缩放因子，四舍五入取整）
    PHYS_X=$(echo "scale=0; ($X * $SCALE + 0.5) / 1" | bc)
    PHYS_Y=$(echo "scale=0; ($Y * $SCALE + 0.5) / 1" | bc)
    PHYS_W=$(echo "scale=0; ($W * $SCALE + 0.5) / 1" | bc)
    PHYS_H=$(echo "scale=0; ($H * $SCALE + 0.5) / 1" | bc)

    CROP_GEOM="${PHYS_W}x${PHYS_H}+${PHYS_X}+${PHYS_Y}"

    # 5. 裁剪
    if convert "$FULL_SCREEN" -crop "$CROP_GEOM" +repage "$CROPPED_FILE" 2>/dev/null; then
        wl-copy < "$CROPPED_FILE"
        command -v cliphist >/dev/null && cliphist add < "$CROPPED_FILE" 2>/dev/null
        SIZE=$(identify -format '%wx%h' "$CROPPED_FILE" 2>/dev/null || echo "未知")
        notify-send -a "screenshot" "定格截图成功" "尺寸: $SIZE"
    else
        notify-send --urgency=critical "裁剪失败" "无效选区"
    fi

    rm -f "$FULL_SCREEN" "$CROPPED_FILE" 2>/dev/null
}

# 主逻辑
case "$MODE" in
    live)
        run_live_mode
        ;;
    freeze)
        run_freeze_mode
        ;;
esac
