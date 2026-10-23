#!/usr/bin/env bash
set -euo pipefail
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk}"
export PATH="$JAVA_HOME/bin:$HOME/.local/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"
command -v apktool >/dev/null || { echo "Install apktool"; exit 1; }
WORK="$ROOT/build-apktool"
rm -rf "$WORK"
mkdir -p "$WORK/res/values" "$WORK/res/layout"
cp "$ROOT/AndroidManifest.xml" "$WORK/"
cp -r "$ROOT/res/"* "$WORK/res/" 2>/dev/null || true
cat > "$WORK/apktool.yml" <<'YAML'
version: 2.9.3
apkFileName: overlay.apk
isFrameworkApk: false
usesFramework:
  ids:
  - 1
sdkInfo:
  minSdkVersion: '30'
  targetSdkVersion: '30'
packageInfo:
  forcedPackageId: '127'
versionInfo:
  versionCode: '1'
  versionName: '1.0'
doNotCompress:
- arsc
YAML
apktool b "$WORK" -o "$OUT/overlay-unsigned.apk"
echo "Built: $OUT/overlay-unsigned.apk"
