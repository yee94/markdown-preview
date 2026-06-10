#!/usr/bin/env bash
# Show the Markdown Preview pipeline trace (JSONL).
set -euo pipefail

SANDBOX_LOG="$HOME/Library/Containers/doc.md-preview/Data/Library/Caches/preview-trace.jsonl"
LOCAL_LOG="$HOME/Library/Caches/preview-trace.jsonl"
if [[ -f "$SANDBOX_LOG" ]]; then
  LOG="$SANDBOX_LOG"
else
  LOG="$LOCAL_LOG"
fi

if [[ ! -f "$LOG" ]]; then
  echo "找不到日志文件。"
  echo "预期路径: $SANDBOX_LOG"
  echo "备用路径: $LOCAL_LOG"
  echo ""
  echo "Trace 默认关闭。可用以下任一方式开启："
  echo "  MD_PREVIEW_TRACE=1 /Applications/Markdown\\ Preview.app/Contents/MacOS/Markdown\\ Preview"
  echo "  defaults write doc.md-preview PreviewTraceEnabled -bool YES"
  exit 1
fi

echo "=== $LOG ==="
echo ""
cat "$LOG"
