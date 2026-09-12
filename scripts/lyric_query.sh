#!/bin/bash

if [ -f "/tmp/waybar_lyric.json" ]; then
    lyric=$(cat /tmp/waybar_lyric.json | jq -r '.text')
else
    lyric=""
fi

# ✅ 输出包含 "text" 字段的 JSON
echo "{\"text\": \"$lyric\"}"
