#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FLIP2_ROOT="$(cd "$ROOT/../../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_require_cmd javac zip zipalign apksigner

OUT="$ROOT/dist"
WORK="$ROOT/build"
ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-30/android.jar"
[[ -f "$ANDROID_JAR" ]] || ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-33/android.jar"
[[ -f "$ANDROID_JAR" ]] || { echo "Need android.jar in SDK platforms/android-30 or 33" >&2; exit 1; }

BT="${ANDROID_SDK_ROOT}/build-tools/34.0.0"
[[ -d "$BT" ]] || BT="${ANDROID_SDK_ROOT}/build-tools/33.0.0"
AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/classes" "$WORK/res" "$OUT"

javac -source 1.8 -target 1.8 \
  -bootclasspath "$ANDROID_JAR":"$BT/core-lambda-stubs.jar" \
  -d "$WORK/classes" "$ROOT/src/com/tim/flip2/nullkeyboard/NullKeyboardService.java"

cd "$WORK/classes" && jar cf "$WORK/classes.jar" com/ && cd "$ROOT"
"$D8" --lib "$ANDROID_JAR" --output "$WORK" "$WORK/classes.jar"

mkdir -p "$WORK/res/xml" "$WORK/res/values"
cp "$ROOT/res/xml/method.xml" "$WORK/res/xml/"
cp "$ROOT/res/values/"*.xml "$WORK/res/values/"

"$AAPT2" compile --dir "$WORK/res" -o "$WORK/res.zip"
"$AAPT2" link -o "$OUT/nullkeyboard-unsigned.apk" \
  --manifest "$ROOT/AndroidManifest.xml" \
  -I "$ANDROID_JAR" \
  --java "$WORK/gen" \
  --min-sdk-version 26 \
  --target-sdk-version 30 \
  "$WORK/res.zip"

zip -j "$OUT/nullkeyboard-unsigned.apk" "$WORK/classes.dex" >/dev/null

"$ZIPALIGN" -f -p 4 "$OUT/nullkeyboard-unsigned.apk" "$OUT/nullkeyboard-aligned.apk"
"$APKSIGNER" sign --ks "$ANDROID_DEBUG_KEY" --ks-pass pass:android \
  --min-sdk-version 26 \
  --out "$OUT/nullkeyboard.apk" "$OUT/nullkeyboard-aligned.apk"
echo "Built: $OUT/nullkeyboard.apk"
