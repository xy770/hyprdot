#!/bin/bash

# 配置文件路径
PROVERBS_FILE="/home/xy770/.config/hypr/scripts/proverbs.txt"

# 检查文件是否存在
if [[ ! -f "$PROVERBS_FILE" ]]; then
    echo "❌ Error: Proverbs file not found at $PROVERBS_FILE"
    echo "💡 Please create it and add one proverb per line."
    exit 1
fi

# 检查文件是否为空
if [[ ! -s "$PROVERBS_FILE" ]]; then
    echo "❌ Error: Proverbs file is empty!"
    exit 1
fi

# 随机选择一条格言并输出
shuf -n1 "$PROVERBS_FILE"
