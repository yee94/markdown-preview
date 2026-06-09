#!/usr/bin/env bash
# Show the Markdown Preview pipeline debug log (when PreviewDebugLog.isEnabled).
set -euo pipefail

LOG="$HOME/Library/Containers/doc.md-preview/Data/Library/Caches/preview-debug.log"

if [[ ! -f "$LOG" ]]; then
  echo "找不到日志文件。"
  echo "预期路径: $LOG"
  echo ""
  echo "PreviewDebugLog.isEnabled 默认为 false。排查时在 PreviewDebugLog.swift 改为 true 并重新 build。"
  exit 1
fi

echo "=== $LOG ==="
echo ""
cat "$LOG"
