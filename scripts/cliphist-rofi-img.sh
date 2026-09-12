#!/usr/bin/env bash
# ~/.config/hypr/scripts/cliphist-rofi-img.sh

tmp_dir="/tmp/cliphist"
rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"

# 临时文件存储 ID（按显示顺序）
id_file=$(mktemp)

# 生成菜单，并将 ID 保存到临时文件
selected_idx=$(cliphist list | head -n 100 | while read -r id content; do
    # 保存 ID
    echo "$id" >> "$id_file"

    if [[ "$content" =~ binary.*(jpg|jpeg|png|bmp) ]]; then
        ext="${BASH_REMATCH[1]}"
        img_file="$tmp_dir/$id.$ext"
        # 解码图片（用于图标预览）
        [[ -f "$img_file" ]] || cliphist decode "$id" > "$img_file" 2>/dev/null
        # 使用 printf 输出带真正空字符的图标标记
        printf "%s\0icon\x1f%s\n" "[Image]" "$img_file"
    else
        preview=$(echo -n "$content" | head -c 80)
        printf "%s\n" "$preview"
    fi
done | rofi -dmenu \
    -p "Clipboard History" \
    -theme "$HOME/.config/rofi/launchers/type-6/clip.rasi" \
    -show-icons \
    -format i)

# 根据 rofi 返回的行号取出对应的 ID
if [[ -n "$selected_idx" ]]; then
    # rofi 行号从 0 开始，sed 行号从 1 开始
    id=$(sed -n "$((selected_idx + 1))p" "$id_file")
    cliphist decode "$id" | wl-copy
fi

# 清理临时文件
rm -f "$id_file"
