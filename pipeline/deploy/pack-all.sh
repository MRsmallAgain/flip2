#!/usr/bin/env bash
# Tier D: assemble dist/flip2-packages-<version>/ — per-component Magisk zips,
# standalone APKs, home-keys.json, SHA256SUMS and an install-order README.
# Reads component paths from manifest.json; never installs anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DIST="$ROOT/pipeline/deploy/dist"

usage() {
  cat <<EOF
Usage: flip2 pack-all [--out DIR]

Assemble the Tier D bundle: each component's Magisk zip + standalone APKs
+ home-keys.json + SHA256SUMS + README with install order and root
requirements. Nothing is pushed to a device.

  --out DIR   Output directory (default: $DIST/flip2-packages-<version>)
EOF
}

OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "--out needs a path" >&2; exit 1; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

# Bundle version: max versionCode across the manifest's components, stamped
# into the directory name so each package drop is uniquely identifiable.
VERSION="$(jq -r '.version // "dev"' "$MANIFEST")"
[[ -n "$OUT" ]] || OUT="$DIST/flip2-packages-$VERSION"

log() { echo "==> $*"; }

[[ -f "$MANIFEST" ]] || { echo "Missing $MANIFEST" >&2; exit 1; }
mkdir -p "$OUT"

copy_component() {
  local name="$1" src="$2" dest="$3"
  if [[ -f "$ROOT/$src" ]]; then
    cp -f "$ROOT/$src" "$OUT/$dest"
    log "packed $name ($dest)"
  else
    MISSING+=("$name: $ROOT/$src (build with: $(jq -r --arg n "$name" '.components[] | select(.name==$n) | .build // "?"' "$MANIFEST"))")
  fi
}

MISSING=()

# Magisk module zips + user APKs, in manifest install order.
while IFS=$'\t' read -r name artifact src; do
  case "$artifact" in
    magisk-module) copy_component "$name" "$src" "$(basename "$src")" ;;
    user-apk)      copy_component "$name" "$src" "$(basename "$src")" ;;
  esac
done < <(jq -r '.components[] | select(.artifact != "settings-write" and ((.zip // .apk) != null)) | [.name, .artifact, (.zip // .apk)] | @tsv' "$MANIFEST")

# Settings-only component: ship the JSON + a standalone apply script.
if [[ -f "$ROOT/launcher-overlay/home-keys.json" ]]; then
  cp -f "$ROOT/launcher-overlay/home-keys.json" "$OUT/"
  log "packed home_keys (home-keys.json)"
fi

cat > "$OUT/apply-home-keys.sh" <<'HK'
#!/usr/bin/env bash
# Apply home-keys.json -> Settings.Global keyshortcut_* via adb (no root).
# Source of the slot values: launcher-overlay/home-keys.json in the flip2 repo.
set -euo pipefail
JSON="$(cd "$(dirname "$0")" && pwd)/home-keys.json"
[[ -f "$JSON" ]] || { echo "Missing $JSON" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; exit 1; }
python3 - "$JSON" <<'PY'
import json, shlex, subprocess, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
keys = {
    "left": "keyshortcut_leftkey",
    "right": "keyshortcut_rightkey",
    "up": "keyshortcut_upkey",
    "down": "keyshortcut_downkey",
    "shortcuts_bar": "keyshortcut_shortcutsbar",
}
for slot, setting in keys.items():
    v = data.get(slot)
    if v is None or (isinstance(v, str) and not v.strip()):
        continue
    cmd = ["adb", "shell", f"settings put global {setting} {shlex.quote(str(v).strip())}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"Failed {setting}: {r.stderr or r.stdout}")
    print(f"{setting} = {v}")
PY
echo "Done. Press Home and try the right soft key (Shortcuts label)."
HK
chmod +x "$OUT/apply-home-keys.sh"

# SHA256SUMS over everything packed so far.
(
  cd "$OUT"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum > SHA256SUMS
)
log "wrote SHA256SUMS ($(grep -c . "$OUT/SHA256SUMS") files)"

cat > "$OUT/README.md" <<MD
# Flip2 package bundle $VERSION

Per-component Magisk modules + APKs for the TCL Flip 2 (4058G, Android 11,
Magisk 25.2). Verify before installing:

    sha256sum -c SHA256SUMS

## Components and install order

| # | Component | File | Type | Root install | Root runtime | Reboot |
MD

jq -r '.components
  | sort_by(.install_order)[]
  | "| \(.install_order) | \(.name) | \(if .name == "home_keys" then "home-keys.json + apply-home-keys.sh" elif .artifact == "settings-write" then "display_size_forced (settings)" elif .external then (if .external.url then "\(.external.asset) (download from \(.external.url))" else "\(.external.asset) (download from \(.external.repo), tag \(.external.tag))" end) else (.zip // .apk | split("/")[-1]) end) | \(.artifact) | \(.root_install) | \(.root_runtime) | \(.reboot) |"' "$MANIFEST" \
  >> "$OUT/README.md"

cat >> "$OUT/README.md" <<'MD'

## Install notes

- **Magisk modules** (`*-magisk.zip`, `FlipMouse.zip`): flash in the Magisk app
  or `su -c 'magisk --install-module <zip>'`. FlipMouse also needs its
  daemon started after boot — use `flip2 flipmouse install` or the module's
  ondevice-install step (Magisk 25.2 stages modules until reboot).
- **User APKs**: `adb install -r <apk>`. Launcher4 should be set as HOME
  (`cmd package set-home-activity com.tim.flip2.launcher4/com.android.launcher3.Launcher`).
- **Null keyboard**: after install run the settings block below, grant
  RECORD_AUDIO + WRITE_SETTINGS appop, and disable the stock Kika IME
  (`pm disable-user --user 0 com.iqqijni.dvt912key` — root). Vosk STT models
  (~40MB EN + ~75MB UK) are never bundled; push them separately
  (`flip2 ime models`).
- **Forkgram**: not included — download the patched release from
  github.com/MRsmallAgain/TelegramAndroid (tag flip2-13.0.2.0-r1) per GPL.
- **home_keys**: run `./apply-home-keys.sh` with a device connected (no root).
- **display**: `adb shell wm size 321x428` (what the installer bakes into
  `display_size_forced`). The override is re-read at boot, so it persists.
  Undo with `wm size reset`.

### IME settings block (adb shell, root or adb root)

```sh
settings put secure show_ime_with_hard_keyboard 1
settings put secure enabled_input_methods com.tim.flip2.nullkeyboard/.NullKeyboardService
settings put secure default_input_method com.tim.flip2.nullkeyboard/.NullKeyboardService
settings put secure accessibility_soft_keyboard_mode 1
settings put system dtmf_tone 0
settings put system dtmf_tone_type 0
pm grant com.tim.flip2.nullkeyboard android.permission.RECORD_AUDIO
cmd appops set com.tim.flip2.nullkeyboard WRITE_SETTINGS allow
pm disable-user --user 0 com.iqqijni.dvt912key
```

## De-root expectations

Survive de-root: launcher4, null keyboard (APK + settings), Forkgram,
Material Files, home_keys, default HOME/IME.
Dies on de-root: FlipMouse (reads /dev/input), keypad ⌫ keylayout remap,
nav overlay (30px nav bar returns), tagdrawer system placement,
launcher-overlay RRO (Launcher4's baked menu survives).
MD

if (( ${#MISSING[@]} )); then
  echo "" >&2
  echo "WARNING: ${#MISSING[@]} artifact(s) missing from bundle:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  echo "Bundle written with gaps — build the listed targets and rerun." >&2
fi

log "bundle: $OUT"
