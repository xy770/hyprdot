#!/usr/bin/env bash

thumbnail_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbnails"
[ -d "$thumbnail_dir" ] || mkdir -p "$thumbnail_dir"

if ! cliphist list -n 1 &>/dev/null; then
  fuzzel -d --prompt-only "cliphist: please store something first "
  rm -rf "$thumbnail_dir"
  exit
fi

generate_fuzzel_input() {
    cliphist list | awk '
    BEGIN { FS="\t"; OFS="\t" }
    /^[0-9]+\t/ {
        id = $1
        preview = $2
        if (preview ~ /^\[\[ binary data/) {
            # 核心修复：强制用 ID 作为文件名，彻底避开空格和括号
            thumbnail_file = "'"$thumbnail_dir"'/" id
            if (system("test -f \"" thumbnail_file "\"") != 0) {
                system("cliphist decode " id " > \"" thumbnail_file "\" 2>/dev/null")
                if (system("file --mime-type \"" thumbnail_file "\" | grep -q \"image/\"") != 0) {
                    system("rm -f \"" thumbnail_file "\"")
                }
            }
            if (system("test -f \"" thumbnail_file "\"") == 0) {
                print id, preview "\0icon\x1f" thumbnail_file
                next
            }
        }
        print id, preview
    }'
}

item=$(generate_fuzzel_input | fuzzel -d --placeholder "Search clipboard..." --counter --no-sort --with-nth 2)
exit_code=$?

if [ "$exit_code" -eq 19 ]; then
  confirmation=$(echo -e "No\nYes" | fuzzel -d --placeholder "Delete history?" --lines 2)
  [ "$confirmation" == "Yes" ] && rm -f ~/.cache/cliphist/db && rm -rf "$thumbnail_dir"
elif [ "$exit_code" -eq 10 ]; then
  if [ -n "$item" ]; then
    item_id=$(echo "$item" | cut -f1)
    echo "$item_id" | cliphist delete
    rm -f "$thumbnail_dir/${item_id}"
  fi
else
  [ -z "$item" ] || echo "$item" | cliphist decode | wl-copy
fi

find "$thumbnail_dir" -type f | while IFS= read -r thumbnail_file; do
  cliphist_item_id=$(basename "$thumbnail_file")
  if ! cliphist list | cut -f1 | grep -qx "$cliphist_item_id"; then
    rm -f "$thumbnail_file"
  fi
done
