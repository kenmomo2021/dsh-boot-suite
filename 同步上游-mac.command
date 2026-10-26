#!/bin/bash
# 双击运行：同步作者仓库（upstream）→ 本地 mac 分支，并跑全量测试
# DSH 运行中也可以同步，但需要重开 DSH 才生效（同步失败会自动回滚）。
cd "$(dirname "$0")" || exit 1
./tools/sync-upstream.sh --apply "$@"
status=$?
echo
echo "按回车关闭窗口…"
read -r _ || true
exit $status
