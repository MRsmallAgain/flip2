#!/usr/bin/env bash
# Wait for MTK preloader (0e8d:2000) — run BEFORE plugging the phone.
set -euo pipefail
MTK_DIR="${HOME}/.local/share/flip2/mtkclient"
STOCK="${STOCK:-${HOME}/flip2-backups/stock-UPBO-2026-11-02}"
SCATTER="${SCATTER:-${HOME}/Downloads/4058G/MT6739_Android_scatter.txt}"

cd "$MTK_DIR"
export PYTHONPATH="$MTK_DIR${PYTHONPATH:+:$PYTHONPATH}"

cmd="${1:-printgpt}"
shift || true

echo "=== mtkclient waiting for preloader (0e8d:2000) ==="
echo "Command: mtk.py $cmd $*"
echo "Do NOT run flip2-enter-fastboot.sh — stay in preloader mode."
echo "Now: power off phone, hold Vol Up, plug USB."
echo ""

exec python3 mtk.py "$cmd" "$@"
