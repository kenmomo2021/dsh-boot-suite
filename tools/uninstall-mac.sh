#!/usr/bin/env bash
# dsh-boot-suite —— macOS 本地卸载
#
# 只摘掉插件：profile 的 dependencies / bundles / node_modules 链接。
# 用户配置（~/.dsh/dsh-startup.json、chat-wallpaper.json、模板、壁纸资源）默认保留，
# 要清干净请手动删（脚本最后会列出路径）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="desktop"
MODE="apply"

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --profile=*) PROFILE="${arg#*=}" ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "[x] 未知参数：$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"
[ -f "$PROFILE_DIR/package.json" ] || die "没有找到 profile：$PROFILE_DIR"
say "目标 profile：${PROFILE}（${PROFILE_DIR}）"

if pgrep -f "DeepSeek Harness.app/Contents/(MacOS|Frameworks)/" >/dev/null 2>&1; then
  if [ "$MODE" = "check" ]; then
    say "（检查模式）DSH 正在运行 —— 正式卸载前需要 ⌘Q 完全退出"
  else
    die "DeepSeek Harness 还在运行。请 ⌘Q 完全退出后再运行本脚本。"
  fi
fi

if [ "$MODE" = "check" ]; then
  say "会执行：node tools/mac-profile.mjs remove \"$PROFILE_DIR\""
  node "$REPO_ROOT/tools/mac-profile.mjs" status "$PROFILE_DIR" || true
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="$PROFILE_DIR/_backup-uninstall-$TS"
mkdir -p "$BK"
cp "$PROFILE_DIR/package.json" "$BK/"
say "已备份 profile 配置 → $BK"

node "$REPO_ROOT/tools/mac-profile.mjs" remove "$PROFILE_DIR"
say ""
say "卸载完成 —— 重新打开 DeepSeek Harness Desktop 生效。"
say ""
say "用户配置没有删，需要清干净的话手动删这些："
say "  $DSH_HOME/dsh-startup.json"
say "  $DSH_HOME/chat-wallpaper.json"
say "  $DSH_HOME/startup-templates/（如果你导入过自定义模板）"
say "  $DSH_HOME/chat-wallpaper/（壁纸图与视频）"
