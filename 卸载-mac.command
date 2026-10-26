#!/bin/bash
# 双击运行：从 DSH 桌面端卸载 dsh-boot-suite（macOS）
# 运行前请先 ⌘Q 完全退出 DeepSeek Harness。用户配置默认保留。
cd "$(dirname "$0")" || exit 1
./tools/uninstall-mac.sh "$@"
status=$?
echo
echo "按回车关闭窗口…"
read -r _ || true
exit $status
