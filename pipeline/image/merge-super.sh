#!/usr/bin/env bash
# Merge dist/flip2-system-tree into YOUR stock super.img -> dist/super-flip2.img
# Host-only; never ships TCL firmware. See docs/IMAGE-BUILD.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

LP="$ROOT/pipeline/image/lp_tool.py"
INJECT="$ROOT/pipeline/image/inject-tree.sh"
DIST="$ROOT/pipeline/deploy/dist"

usage() {
  cat <<EOF
Usage: flip2 image merge-super --stock-super PATH [options]

  --tree DIR          flip2-system-tree (default: $DIST/flip2-system-tree)
  --out PATH          output super (default: $DIST/super-flip2.img)
  --lp-dir DIR        skip extract; use existing system/product/vendor .img
  --skip-avb          do not run avbtool footers (lab / already signed)
  --work-dir DIR      scratch (default: $DIST/merge-super-work)

Requires: debugfs, e2fsck, resize2fs, python3. Optional: avbtool (vendor or PATH).

Orange / unlocked bootloader: you may still need a non-stock vbmeta_system — see
IMAGE-BUILD.md and your dump's RUN-REPORT.
EOF
}

STOCK=""
TREE="$DIST/flip2-system-tree"
OUT="$DIST/super-flip2.img"
LP_DIR=""
SKIP_AVB=0
WORK="$DIST/merge-super-work"

while [ $# -gt 0 ]; do
  case "$1" in
    --stock-super) STOCK="${2:-}"; shift 2 ;;
    --tree) TREE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --lp-dir) LP_DIR="${2:-}"; shift 2 ;;
    --skip-avb) SKIP_AVB=1; shift ;;
    --work-dir) WORK="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$STOCK" && -f "$STOCK" ]] || { echo "--stock-super required" >&2; usage; exit 1; }
[[ -d "$TREE" ]] || { echo "tree missing: $TREE (run flip2 image build-tree)" >&2; exit 1; }
command -v debugfs e2fsck resize2fs python3 >/dev/null || {
  echo "need debugfs, e2fsck, resize2fs, python3" >&2
  exit 1
}

log() { echo "==> $*"; }

# e2fsck returns 1 when it corrected the fs; that is success under set -e.
e2fsck_ok() {
  local img="$1" rc
  set +e
  e2fsck -fy "$img" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -gt 1 ]]; then
    echo "e2fsck failed on $img (exit $rc)" >&2
    exit "$rc"
  fi
}

avb_footer() {
  local img="$1" part_size="$2"
  local -a cmd=()
  if command -v avbtool >/dev/null 2>&1; then
    cmd=(avbtool)
  elif [[ -f "$ROOT/vendor/android-tools/android-tools-37.0.0p1/vendor/avb/avbtool.py" ]]; then
    cmd=(python3 "$ROOT/vendor/android-tools/android-tools-37.0.0p1/vendor/avb/avbtool.py")
  else
    return 0
  fi
  log "avbtool hashtree footer: $(basename "$img")"
  "${cmd[@]}" erase_footer --image "$img" 2>/dev/null || true
  "${cmd[@]}" add_hashtree_footer \
    --image "$img" \
    --partition_size "$part_size" \
    --partition_name "$(basename "$img" .img)" \
    --algorithm NONE \
    --do_not_generate_fec 2>/dev/null || {
    echo "WARN: avbtool failed for $img (use --skip-avb or install avbtool)" >&2
  }
}

grow_if_needed() {
  local img="$1" tree_sub="$2"
  local src="$TREE/$tree_sub"
  [[ -d "$src" ]] || return 0
  local need_kb
  need_kb="$(du -sk "$src" | awk '{print $1}')"
  local free_blocks block_size
  free_blocks="$(debugfs -R stats "$img" 2>&1 | awk '/Free blocks/{print $3}' | tr -d ',')"
  block_size="$(debugfs -R stats "$img" 2>&1 | awk '/Block size/{print $3}')"
  [[ -n "$free_blocks" && -n "$block_size" ]] || {
    echo "could not read ext4 stats for $img" >&2
    exit 1
  }
  local free_bytes=$((free_blocks * block_size))
  local need_bytes=$((need_kb * 1024 + 32 * 1024 * 1024))
  if (( free_bytes >= need_bytes )); then
    log "$(basename "$img"): enough free ($free_bytes bytes)"
    return 0
  fi
  local cur_size new_size
  cur_size="$(stat -c%s "$img")"
  new_size=$((cur_size + need_bytes - free_bytes))
  new_size=$(( (new_size + 4095) / 4096 * 4096 ))
  log "grow $(basename "$img") $cur_size -> $new_size"
  truncate -s "$new_size" "$img"
  e2fsck_ok "$img"
  resize2fs "$img" >/dev/null
  e2fsck_ok "$img"
}

rm -rf "$WORK"
mkdir -p "$WORK/lp"

if [[ -n "$LP_DIR" ]]; then
  log "using lp-dir $LP_DIR"
  cp -a "$LP_DIR/system.img" "$WORK/lp/system.img"
  cp -a "$LP_DIR/product.img" "$WORK/lp/product.img"
  [[ -f "$LP_DIR/vendor.img" ]] && cp -a "$LP_DIR/vendor.img" "$WORK/lp/vendor.img" || true
else
  log "LP extract from stock super"
  python3 "$LP" extract "$STOCK" -o "$WORK/lp" --only system product vendor
fi

SYS="$WORK/lp/system.img"
PROD="$WORK/lp/product.img"
[[ -f "$SYS" && -f "$PROD" ]] || { echo "missing system/product in lp" >&2; exit 1; }

cp -a "$SYS" "$WORK/system.img"
cp -a "$PROD" "$WORK/product.img"

grow_if_needed "$WORK/system.img" system
grow_if_needed "$WORK/product.img" product

log "inject flip2 tree"
chmod +x "$INJECT"
"$INJECT" --system "$WORK/system.img" --product "$WORK/product.img" --tree "$TREE"

e2fsck_ok "$WORK/system.img"
e2fsck_ok "$WORK/product.img"

SYS_OUT="$WORK/system-avb.img"
PROD_OUT="$WORK/product-avb.img"
cp -a "$WORK/system.img" "$SYS_OUT"
cp -a "$WORK/product.img" "$PROD_OUT"

if [[ "$SKIP_AVB" -eq 0 ]]; then
  avb_footer "$SYS_OUT" "$(stat -c%s "$SYS_OUT")"
  avb_footer "$PROD_OUT" "$(stat -c%s "$PROD_OUT")"
fi

log "repack super -> $OUT"
mkdir -p "$(dirname "$OUT")"
python3 "$LP" repack "$STOCK" \
  --out "$OUT" \
  --allow-larger \
  -p "system=$SYS_OUT" \
  -p "product=$PROD_OUT"

sha256sum "$OUT" | tee "$OUT.sha256"
log "done: $OUT"
