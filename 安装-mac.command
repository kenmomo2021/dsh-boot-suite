#!/bin/bash
# 双击运行：把 dsh-boot-suite 装进 DSH 桌面端（macOS，link 方式）
# 运行前请先 ⌘Q 完全退出 DeepSeek Harness。
cd "$(dirname "$0")" || exit 1
./tools/install-mac.sh "$@"
status=$?
echo
echo "按回车关闭窗口…"
read -r _ || true
exit $status
