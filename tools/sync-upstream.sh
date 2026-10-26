#!/usr/bin/env bash
# dsh-boot-suite —— 同步作者仓库（upstream）到本地 mac 分支
#
# 分支模型：
#   main   = 作者仓库的镜像（只 fast-forward，不改一行）
#   mac    = main + 本地 macOS 适配提交（默认检出这个分支）
# 同步 = 把 mac rebase 到 upstream/main 上，然后跑全量测试；冲突或测试失败自动回滚。
#
# 用法：
#   ./tools/sync-upstream.sh            # 只检查，不改任何东西（默认）
#   ./tools/sync-upstream.sh --apply    # 同步 + 跑测试（DSH 运行中也可以，需自己重开 DSH）
#   ./tools/sync-upstream.sh --auto     # 给 launchd 用：DSH 运行中/工作区脏就跳过
#   ./tools/sync-upstream.sh --apply --push   # 顺带推到自己的 fork（需要先配好 origin）
#
# 日志：~/.dsh/boot-suite-mac-sync.log
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="check"
DO_PUSH=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --auto) MODE="auto" ;;
    --push) DO_PUSH=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "[x] 未知参数：$arg" >&2; exit 2 ;;
  esac
done

# launchd 环境的 PATH 很干净：补上 node/npm/git
if ! command -v node >/dev/null 2>&1; then
  NODE_BIN=""
  for d in "$HOME"/.nvm/versions/node/*/bin "$HOME"/.volta/bin /opt/homebrew/bin /usr/local/bin; do
    [ -x "$d/node" ] && NODE_BIN="$d"
  done
  [ -n "$NODE_BIN" ] && PATH="$NODE_BIN:$PATH"
fi
[ -d /opt/homebrew/bin ] && PATH="/opt/homebrew/bin:$PATH"
export PATH

LOG="${DSH_HOME:-$HOME/.dsh}/boot-suite-mac-sync.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() {
  local line
  line="[$(date '+%F %T')] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG" 2>/dev/null || true
}
notify() {
  if [ "$MODE" = "auto" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"dsh-boot-suite 同步\"" >/dev/null 2>&1 || true
  fi
}
die() { log "[x] $*"; notify "同步中止"; exit 1; }

# 测试失败时回滚：当前安装是 link 指向工作区，留着坏代码会直接影响下次打开 DSH。
# 失败现场存到 mac-sync-failed 分支，一条都没丢，方便事后排查。
rollback_sync() {
  git branch -f mac-sync-failed HEAD >/dev/null 2>&1 || true
  git reset --hard "$PRE_SYNC_REV" >/dev/null 2>&1 || true
  log "[x] npm test 失败，已回滚到同步前（${PRE_SYNC_REV}）"
  log "    失败现场保留在 mac-sync-failed 分支：git log --oneline mac-sync-failed / git diff mac mac-sync-failed"
  notify "测试失败，已回滚"
  exit 1
}

[ -d .git ] || die "不是 git 仓库：$REPO_ROOT"
git remote get-url upstream >/dev/null 2>&1 || die "缺少 upstream 远端。先执行：git remote add upstream https://github.com/LeeRolling/dsh-boot-suite.git"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$CURRENT_BRANCH" = "mac" ] || die "当前在 $CURRENT_BRANCH 分支，请先 git switch mac"
git remote get-url upstream >/dev/null 2>&1
git fetch upstream --prune --tags --quiet

UPSTREAM_REV="$(git rev-parse --short upstream/main)"
BEHIND="$(git rev-list --count HEAD..upstream/main)"
DIRTY="$(git status --porcelain | wc -l | tr -d ' ')"
DSH_RUNNING=0
pgrep -f "DeepSeek Harness.app/Contents/(MacOS|Frameworks)/" >/dev/null 2>&1 && DSH_RUNNING=1

if [ "$MODE" = "check" ]; then
  echo "仓库      : $REPO_ROOT"
  echo "当前分支  : ${CURRENT_BRANCH}（$(git rev-parse --short HEAD) $(git log -1 --format=%s)）"
  echo "upstream  : $UPSTREAM_REV $(git log -1 --format=%s upstream/main)"
  echo "落后提交  : $BEHIND"
  echo "工作区    : $([ "$DIRTY" = 0 ] && echo 干净 || echo "有 $DIRTY 个未提交改动")"
  echo "DSH 状态  : $([ "$DSH_RUNNING" = 1 ] && echo 运行中 || echo 未运行)"
  if [ "$BEHIND" = 0 ]; then
    echo "结论      : 已是最新"
  else
    echo "结论      : 可同步。执行 ./tools/sync-upstream.sh --apply"
    echo "上游新提交："
    git log --oneline HEAD..upstream/main | head -20 | sed 's/^/  /'
  fi
  exit 0
fi

[ "$DIRTY" = 0 ] || die "工作区有未提交改动，先 commit / stash 再同步"
if [ "$MODE" = "auto" ] && [ "$DSH_RUNNING" = 1 ] && [ "$FORCE" = 0 ]; then
  log "DSH 正在运行，跳过本次同步（下次自动重试）"
  exit 0
fi
if [ "$BEHIND" = 0 ]; then
  log "已是最新：$UPSTREAM_REV"
  exit 0
fi

PRE_SYNC_REV="$(git rev-parse HEAD)"
log "开始同步：mac 落后 upstream/main $BEHIND 个提交（目标 ${UPSTREAM_REV}）"
if ! git rebase upstream/main; then
  git rebase --abort || true
  log "[x] rebase 冲突，已回滚到同步前状态 —— 需要手动处理（git status / git rebase upstream/main）"
  notify "rebase 冲突，已回滚"
  exit 1
fi
log "rebase 完成：$(git log --oneline -1)"

# 测试时清掉外部 DSH_HOME：作者的部分 smoke 会自己建临时 HOME，
# 外部 DSH_HOME 会污染它们（实测会出现 1 项误报）。
if [ "$MODE" = "auto" ]; then
  if ! ( unset DSH_HOME; npm test ) >>"$LOG" 2>&1; then rollback_sync; fi
else
  if ! ( unset DSH_HOME; npm test ); then rollback_sync; fi
fi


# main 只是 upstream 的镜像，同步后强制指过去（不检出、不改工作区）
git branch -f main upstream/main

if [ "$DO_PUSH" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
  log "推送到 origin（main + mac）…"
  git push origin main >/dev/null 2>&1 || log "[!] 推送 main 失败（网络？）"
  if ! git push --force-with-lease origin mac >/dev/null 2>&1; then
    log "[!] 推送 mac 失败（网络？）。本地已同步，不影响使用。"
  fi
fi

log "同步完成（${UPSTREAM_REV}）。重开 DSH 后生效。"
notify "同步完成，重开 DSH 生效"
