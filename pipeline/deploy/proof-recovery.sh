#!/usr/bin/env bash
# A9: non-destructive recovery proof (host-side).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$ROOT/bin:$PATH"
cd "$ROOT"
FAIL=0
run() { echo "==> $*"; "$@" || FAIL=1; }

run flip2 wizard check
run node --check wizard/pages/js/pipeline.js
run bash -n pipeline/wizard/render.sh
run bash -n pipeline/deploy/emit.sh
run bash -n pipeline/deploy/emit-first-boot.sh

MD5="$(md5sum pipeline/wallpaper/assets/flip2-wallpaper.png | awk '{print $1}')"
[[ "$MD5" == "d0eb46bc33e2751940150abf72b93c5f" ]] || { echo "FAIL: wallpaper md5 $MD5"; FAIL=1; }

VC="$(jq -r '.versionCode' pipeline/deploy/manifest.json)"
[[ "$VC" == "20261029" ]] || { echo "FAIL: versionCode $VC"; FAIL=1; }

for z in pipeline/deploy/dist/flip2-installer-clean-magisk.zip pipeline/deploy/dist/flip2-installer-full-magisk.zip; do
  if [[ -f "$z" ]]; then
    if unzip -l "$z" 2>/dev/null | grep -qiE 'intertune|bouncy'; then
      echo "FAIL: wizard APK in $z"
      FAIL=1
    else
      echo "OK: no wizard-only APKs in $(basename "$z")"
    fi
  fi
done

echo ""
[[ "$FAIL" -eq 0 ]] && echo "PROOF PASS" && exit 0
echo "PROOF FAIL"
exit 1
