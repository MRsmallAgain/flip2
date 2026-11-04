#!/usr/bin/env bash
# Inject flip2-system-tree into raw system.img / product.img via debugfs (no loop mount).
set -euo pipefail

usage() {
  cat <<EOF
Usage: inject-tree.sh --system IMG --product IMG --tree DIR

  Copies tree/system/* into system image (system-as-root: /app, /usr, …) and
  tree/product/* into product image (/overlay, …).
EOF
}

SYSTEM=""
PRODUCT=""
TREE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --system) SYSTEM="${2:-}"; shift 2 ;;
    --product) PRODUCT="${2:-}"; shift 2 ;;
    --tree) TREE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$SYSTEM" && -n "$PRODUCT" && -n "$TREE" && -d "$TREE" ]] || {
  echo "need --system --product --tree" >&2
  usage
  exit 1
}
command -v debugfs >/dev/null || { echo "debugfs required" >&2; exit 1; }

debugfs_mkdir_p() {
  local img="$1" path="$2"
  local cur="" part
  path="${path#/}"
  IFS=/ read -ra parts <<< "$path"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    cur="${cur}/${part}"
    debugfs -w -R "mkdir $cur" "$img" 2>/dev/null || true
  done
}

inject_files() {
  local img="$1" local src="$2"
  [[ -d "$src" ]] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    dest="/${rel}"
    parent="$(dirname "$dest")"
    debugfs_mkdir_p "$img" "$parent"
    debugfs -w -R "rm $dest" "$img" 2>/dev/null || true
    debugfs -w -R "write $f $dest" "$img"
    if [[ -x "$f" ]]; then
      debugfs -w -R "set_inode_field $dest mode 0100755" "$img" 2>/dev/null || true
    else
      debugfs -w -R "set_inode_field $dest mode 0100644" "$img" 2>/dev/null || true
    fi
  done < <(find "$src" -type f -print0)
}

log() { echo "==> inject: $*"; }

if [[ -d "$TREE/system" ]]; then
  log "system -> $SYSTEM"
  inject_files "$SYSTEM" "$TREE/system"
fi
if [[ -d "$TREE/product" ]]; then
  log "product -> $PRODUCT"
  inject_files "$PRODUCT" "$TREE/product"
fi

echo "inject-tree done"
