#!/usr/bin/env bash
# Build Flip2 Null Keyboard APK (T9 + symbols + offline STT: Whisper + Vosk).
# Native libs: vendor/jni/armeabi-v7a/{libvosk.so,libjnidispatch.so,
#             libwhisper.so,libwhisperjni.so}
# Models are NOT packaged — push with: flip2 ime whisper / flip2 ime models
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FLIP2_ROOT="$(cd "$ROOT/../../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_require_cmd javac zip zipalign apksigner

OUT="$ROOT/dist"
WORK="$ROOT/build"
VENDOR="$ROOT/vendor"
ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-30/android.jar"
[[ -f "$ANDROID_JAR" ]] || ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-33/android.jar"
[[ -f "$ANDROID_JAR" ]] || { echo "Need android.jar in SDK platforms/android-30 or 33" >&2; exit 1; }

BT="${ANDROID_SDK_ROOT}/build-tools/34.0.0"
[[ -d "$BT" ]] || BT="${ANDROID_SDK_ROOT}/build-tools/33.0.0"
AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"

[[ -f "$VENDOR/jars/vosk-android.jar" ]] || { echo "Missing $VENDOR/jars/vosk-android.jar — restore vendor/" >&2; exit 1; }
[[ -f "$VENDOR/jars/jna.jar" ]] || { echo "Missing $VENDOR/jars/jna.jar — restore vendor/" >&2; exit 1; }
[[ -f "$VENDOR/jni/armeabi-v7a/libvosk.so" ]] || { echo "Missing libvosk.so" >&2; exit 1; }
[[ -f "$VENDOR/jni/armeabi-v7a/libjnidispatch.so" ]] || { echo "Missing libjnidispatch.so" >&2; exit 1; }
[[ -f "$VENDOR/jni/armeabi-v7a/libwhisper.so" ]] || { echo "Missing libwhisper.so" >&2; exit 1; }
[[ -f "$VENDOR/jni/armeabi-v7a/libwhisperjni.so" ]] || { echo "Missing libwhisperjni.so" >&2; exit 1; }

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/classes" "$WORK/res" "$OUT"

CP="$VENDOR/jars/vosk-android.jar:$VENDOR/jars/jna.jar:$ANDROID_JAR"

javac -source 1.8 -target 1.8 \
  -bootclasspath "$ANDROID_JAR":"$BT/core-lambda-stubs.jar" \
  -classpath "$CP" \
  -d "$WORK/classes" \
  "$ROOT/src/com/tim/flip2/nullkeyboard/"*.java

cd "$WORK/classes" && jar cf "$WORK/classes.jar" com/ && cd "$ROOT"
"$D8" --lib "$ANDROID_JAR" --classpath "$VENDOR/jars/vosk-android.jar" \
  --classpath "$VENDOR/jars/jna.jar" --output "$WORK" \
  "$WORK/classes.jar" "$VENDOR/jars/vosk-android.jar" "$VENDOR/jars/jna.jar"

mkdir -p "$WORK/res/xml" "$WORK/res/values" "$WORK/res/raw"
cp "$ROOT/res/xml/method.xml" "$WORK/res/xml/"
cp "$ROOT/res/values/"*.xml "$WORK/res/values/"
if [[ -d "$ROOT/res/raw" ]]; then
  cp "$ROOT/res/raw/"* "$WORK/res/raw/" 2>/dev/null || true
fi

"$AAPT2" compile --dir "$WORK/res" -o "$WORK/res.zip"
"$AAPT2" link -o "$OUT/nullkeyboard-unsigned.apk" \
  --manifest "$ROOT/AndroidManifest.xml" \
  -I "$ANDROID_JAR" \
  --java "$WORK/gen" \
  --min-sdk-version 26 \
  --target-sdk-version 30 \
  "$WORK/res.zip"

# DEX + native libs into APK (Android loads from lib/<abi>/)
zip -j "$OUT/nullkeyboard-unsigned.apk" "$WORK/classes.dex" >/dev/null
mkdir -p "$WORK/lib/armeabi-v7a"
for lib in libvosk.so libjnidispatch.so libwhisper.so libwhisperjni.so; do
  cp "$VENDOR/jni/armeabi-v7a/$lib" "$WORK/lib/armeabi-v7a/"
done
(
  cd "$WORK"
  zip -u "$OUT/nullkeyboard-unsigned.apk" \
    "lib/armeabi-v7a/libvosk.so" \
    "lib/armeabi-v7a/libjnidispatch.so" \
    "lib/armeabi-v7a/libwhisper.so" \
    "lib/armeabi-v7a/libwhisperjni.so" >/dev/null
)

"$ZIPALIGN" -f -p 4 "$OUT/nullkeyboard-unsigned.apk" "$OUT/nullkeyboard-aligned.apk"
"$APKSIGNER" sign --ks "$ANDROID_DEBUG_KEY" --ks-pass pass:android \
  --min-sdk-version 26 \
  --out "$OUT/nullkeyboard.apk" "$OUT/nullkeyboard-aligned.apk"
echo "Built: $OUT/nullkeyboard.apk"
ls -lh "$OUT/nullkeyboard.apk"
