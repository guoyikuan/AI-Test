#!/bin/bash
# 飞书PRD快速获取脚本
# 用法: ./get_prd.sh <飞书URL> [输出格式]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_PATH="$SCRIPT_DIR/fetch_prd.py"

if [ ! -f "$TOOL_PATH" ]; then
    echo "❌ 错误: 找不到fetch_prd.py工具"
    exit 1
fi

if [ -z "$1" ]; then
    echo "📋 飞书PRD快速获取工具"
    echo ""
    echo "用法: $0 <飞书URL> [输出格式]"
    echo ""
    echo "参数:"
    echo "  <飞书URL>    - 飞书Wiki文档URL"
    echo "  [输出格式]   - json (默认) | excel | markdown"
    echo ""
    echo "示例:"
    echo "  $0 'https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ'"
    echo "  $0 'https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ' excel"
    echo ""
    exit 1
fi

URL="$1"
FORMAT="${2:-json}"

echo "🚀 正在获取PRD文档..."
echo "   URL: $URL"
echo "   格式: $FORMAT"
echo ""

python3 "$TOOL_PATH" "$URL" --format "$FORMAT"

echo ""
echo "✓ 完成！"
