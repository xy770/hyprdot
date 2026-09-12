#!/bin/bash
echo "=== $(date) ==="
echo "全部参数: $@"
echo "DUNST_APP_NAME = $DUNST_APP_NAME"
echo "WAYLAND_DISPLAY = $WAYLAND_DISPLAY"
echo "DBUS_SESSION_BUS_ADDRESS = $DBUS_SESSION_BUS_ADDRESS"

case "$DUNST_APP_NAME" in
    screenshot)
        echo "进入 screenshot 分支"
        # 确保环境变量
        if [ -z "$WAYLAND_DISPLAY" ]; then
            export WAYLAND_DISPLAY="wayland-0"
        fi
        if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
        fi

        # 检查剪贴板是否有图片
        if ! wl-paste -t image/png -l 2>/dev/null | grep -q image; then
            echo "剪贴板中无图片"
            exit 1
        fi

        TMPFILE="/tmp/swappy-edit-$(date +%s).png"
        echo "保存到临时文件: $TMPFILE"
        wl-paste -t image/png > "$TMPFILE"
        if [ $? -ne 0 ] || [ ! -s "$TMPFILE" ]; then
            echo "保存图片失败或文件为空"
            rm -f "$TMPFILE"
            exit 1
        fi
        echo "文件大小: $(stat -c %s "$TMPFILE")"

        echo "启动 swappy..."
        swappy -f "$TMPFILE" &
        SWAPPY_PID=$!
        sleep 1
        if kill -0 $SWAPPY_PID 2>/dev/null; then
            echo "swappy 进程仍在运行"
        else
            echo "swappy 进程已退出"
        fi

        # 延迟删除临时文件
        (sleep 60 && rm -f "$TMPFILE") &
        ;;
    *)
        echo "未匹配的应用: $DUNST_APP_NAME"
        ;;
esac
