#!/usr/bin/env bash
# dsh-boot-suite —— macOS 本地安装（link 方式，改代码即生效）
#
# 用法：
#   ./tools/install-mac.sh              # 安装到 desktop profile
#   ./tools/install-mac.sh --check      # 只看计划，不动任何东西
#   ./tools/install-mac.sh --profile=web
#
# 设计对应作者 Windows 版的 tools/install.ps1：
#   · 先要求完全退出 DSH（desktop profile 的 package.json 由桌面端进程锁着）
#   · 备份 profile 的 package.json / pnpm-lock.yaml
#   · 以 link: 方式登记插件 + 修正 dsh.profile.bundles
#   · 装完不自动启动 DSH（作者红线：安装助手只安装）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="desktop"
MODE="apply"

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --profile=*) PROFILE="${arg#*=}" ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "[x] 未知参数：$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

[ -f "$REPO_ROOT/package.json" ] && [ -f "$REPO_ROOT/lib/index.js" ] || die "这不像插件目录：$REPO_ROOT"
VERSION="$(node -p "require(process.argv[1]).version" "$REPO_ROOT/package.json")"
say "dsh-boot-suite v$VERSION"
say "仓库位置：$REPO_ROOT"

# ── 1. 找 DSH 命令行（找不到也能装，只是参考信息）──────────────────────────
DSH_CLI=""
for c in \
  "/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh" \
  "$HOME/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"; do
  [ -x "$c" ] && DSH_CLI="$c" && break
done
if [ -z "$DSH_CLI" ] && command -v dsh >/dev/null 2>&1; then DSH_CLI="$(command -v dsh)"; fi
if [ -n "$DSH_CLI" ]; then say "DSH 命令行：$DSH_CLI"; else say "[!] 没找到 DSH 命令行 —— 不影响安装（改 profile 配置即可）"; fi

# ── 2. 找 profile ───────────────────────────────────────────────────────────
PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"
[ -f "$PROFILE_DIR/package.json" ] || die "没有找到 profile：$PROFILE_DIR
    请先打开一次 DeepSeek Harness Desktop（让它初始化 profile），完全退出后再运行。"
say "目标 profile：${PROFILE}（${PROFILE_DIR}）"

# ── 3. 桌面端必须先完全退出 ─────────────────────────────────────────────────
DSH_RUNNING=0
if pgrep -f "DeepSeek Harness.app/Contents/(MacOS|Frameworks)/" >/dev/null 2>&1; then DSH_RUNNING=1; fi
if [ "$DSH_RUNNING" -eq 1 ]; then
  if [ "$MODE" = "check" ]; then
    say "（检查模式）DSH 正在运行 —— 正式安装前需要 ⌘Q 完全退出"
  else
    die "DeepSeek Harness 还在运行。请 ⌘Q 完全退出（菜单栏图标也要退）后再运行本脚本。"
  fi
fi

# ── 4. 备份 profile ─────────────────────────────────────────────────────────
if [ "$MODE" = "apply" ]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  BK="$PROFILE_DIR/_backup-install-$TS"
  mkdir -p "$BK"
  cp "$PROFILE_DIR/package.json" "$BK/"
  [ -f "$PROFILE_DIR/pnpm-lock.yaml" ] && cp "$PROFILE_DIR/pnpm-lock.yaml" "$BK/" || true
  say "已备份 profile 配置 → $BK"
fi

# 顺手清掉之前 Plugin Hub 留下的悬空链接（指向 ../https:/github.com/... 那种）
DANGLING="$PROFILE_DIR/node_modules/dsh-boot-suite"
if [ -L "$DANGLING" ] && [ ! -e "$DANGLING" ]; then
  say "清理悬空链接：$DANGLING -> $(readlink "$DANGLING")"
  [ "$MODE" = "apply" ] && rm -f "$DANGLING"
fi

if [ "$MODE" = "check" ]; then
  say ""
  say "检查完毕 —— 没有修改任何东西。"
  say "会执行：node tools/mac-profile.mjs add \"$PROFILE_DIR\" \"$REPO_ROOT\""
  say "        （写 dependencies[link:] + dsh.profile.bundles + node_modules 链接；并卸掉旧插件 dsh-startup-screen / dsh-chat-wallpaper）"
  node "$REPO_ROOT/tools/mac-profile.mjs" status "$PROFILE_DIR" || true
  exit 0
fi

# ── 5. 装（link 方式）───────────────────────────────────────────────────────
say ""
say "[1/2] 登记插件到 profile（link 方式）…"
node "$REPO_ROOT/tools/mac-profile.mjs" add "$PROFILE_DIR" "$REPO_ROOT"

say "[2/2] 自检…"
node "$REPO_ROOT/tools/mac-profile.mjs" status "$PROFILE_DIR" >/dev/null || die "自检失败：profile 配置没写对，请把上面的输出发出来"
INSTALLED_VERSION="$(node -p "require('$PROFILE_DIR/node_modules/dsh-boot-suite/package.json').version")"
say "  装好了：node_modules/dsh-boot-suite -> ${REPO_ROOT}（v${INSTALLED_VERSION}）"

if [ -f "$DSH_HOME/dsh-startup.json" ] || [ -f "$DSH_HOME/chat-wallpaper.json" ]; then
  say "  检测到已有用户配置（dsh-startup.json / chat-wallpaper.json），不会覆盖。"
fi

say ""
say "完成 —— 现在手动打开 DeepSeek Harness Desktop，确认三件事："
say "  1) 设置页里多出「启动动画」和「聊天背景」两项"
say "  2) 冷启动会播开机动画（第一幕 + 第二幕）"
say "  3) 动画结束后落在聊天底图上（大字横幅可选）"
say ""
say "出问题：先 ⌘Q 退出 DSH，再运行 ./卸载-mac.command；日志在 $DSH_HOME/boot-suite-diag.log"
