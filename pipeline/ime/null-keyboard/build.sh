#!/usr/bin/env bash
# Build Flip2 Null Keyboard APK (T9 + symbols + offline STT: Sherpa-ONNX streaming).
# Native libs: vendor/jni/armeabi-v7a/{libonnxruntime.so,libsherpa-onnx-jni.so}
# Run vendor/fetch-sherpa.sh first. Models NOT in APK — flip2 ime sherpa
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

	[[ -f "$VENDOR/jars/sherpa-onnx-classes.jar" ]] || { echo "Missing sherpa — run vendor/fetch-sherpa.sh" >&2; exit 1; }
	[[ -f "$VENDOR/jars/kotlin-stdlib.jar" ]] || { echo "Missing kotlin-stdlib.jar in vendor/jars" >&2; exit 1; }
	[[ -f "$VENDOR/jni/armeabi-v7a/libonnxruntime.so" ]] || { echo "Missing libonnxruntime.so — run vendor/fetch-sherpa.sh" >&2; exit 1; }
	[[ -f "$VENDOR/jni/armeabi-v7a/libsherpa-onnx-jni.so" ]] || { echo "Missing libsherpa-onnx-jni.so" >&2; exit 1; }

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/classes" "$WORK/res" "$OUT"

CP="$VENDOR/jars/sherpa-onnx-classes.jar:$VENDOR/jars/kotlin-stdlib.jar:$ANDROID_JAR"

javac -source 1.8 -target 1.8 \
  -bootclasspath "$ANDROID_JAR":"$BT/core-lambda-stubs.jar" \
  -classpath "$CP" \
  -d "$WORK/classes" \
  "$ROOT/src/com/tim/flip2/nullkeyboard/"*.java

cd "$WORK/classes" && jar cf "$WORK/classes.jar" com/ && cd "$ROOT"
"$D8" --lib "$ANDROID_JAR" \
  --classpath "$VENDOR/jars/sherpa-onnx-classes.jar" \
  --classpath "$VENDOR/jars/kotlin-stdlib.jar" \
  --output "$WORK" \
  "$WORK/classes.jar" "$VENDOR/jars/sherpa-onnx-classes.jar" "$VENDOR/jars/kotlin-stdlib.jar"

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
for lib in libonnxruntime.so libsherpa-onnx-jni.so; do
  cp "$VENDOR/jni/armeabi-v7a/$lib" "$WORK/lib/armeabi-v7a/"
done
(
  cd "$WORK"
  zip -u "$OUT/nullkeyboard-unsigned.apk" \
    "lib/armeabi-v7a/libonnxruntime.so" \
    "lib/armeabi-v7a/libsherpa-onnx-jni.so" >/dev/null
)

"$ZIPALIGN" -f -p 4 "$OUT/nullkeyboard-unsigned.apk" "$OUT/nullkeyboard-aligned.apk"
"$APKSIGNER" sign --ks "$ANDROID_DEBUG_KEY" --ks-pass pass:android \
  --min-sdk-version 26 \
  --out "$OUT/nullkeyboard.apk" "$OUT/nullkeyboard-aligned.apk"
echo "Built: $OUT/nullkeyboard.apk"
ls -lh "$OUT/nullkeyboard.apk"
