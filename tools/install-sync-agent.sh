#!/usr/bin/env bash
# dsh-boot-suite —— 给「时刻同步」装一个 launchd 定时任务（默认每小时）
#
#   ./tools/install-sync-agent.sh                 # 安装，每小时检查一次
#   ./tools/install-sync-agent.sh --interval=1800 # 每 30 分钟
#   ./tools/install-sync-agent.sh --uninstall     # 卸掉
#
# 任务行为 = tools/sync-upstream.sh --auto：
#   · DSH 正在运行 → 跳过（避免边用边换文件）
#   · 工作区有未提交改动 → 跳过
#   · 有新版就 rebase + 跑 npm test；冲突或测试失败自动回滚，并发 macOS 通知
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.local.dsh-boot-suite-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL=3600
UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --interval=*) INTERVAL="${arg#*=}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "[x] 未知参数：$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }

if [ "$UNINSTALL" = 1 ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  say "已卸载定时同步：$LABEL"
  exit 0
fi

[ -x "$REPO_ROOT/tools/sync-upstream.sh" ] || { echo "[x] 找不到 tools/sync-upstream.sh" >&2; exit 1; }
DSH_DIR="${DSH_HOME:-$HOME/.dsh}"
mkdir -p "$HOME/Library/LaunchAgents" "$DSH_DIR"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>exec '$REPO_ROOT/tools/sync-upstream.sh' --auto</string>
  </array>
  <key>StartInterval</key>
  <integer>$INTERVAL</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$DSH_DIR/boot-suite-mac-sync.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$DSH_DIR/boot-suite-mac-sync.launchd.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"

say "已安装定时同步：${LABEL}（每 ${INTERVAL}s 一次）"
say "  脚本：$REPO_ROOT/tools/sync-upstream.sh --auto"
say "  日志：$DSH_DIR/boot-suite-mac-sync.log"
say "  卸载：$REPO_ROOT/tools/install-sync-agent.sh --uninstall"
