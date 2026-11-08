#!/usr/bin/env bash
# Build flip2-gamepad daemon -> Magisk module zip (same NDK/libevdev pattern as FlipMouse).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GP="$FLIP2_ROOT/pipeline/landscape-gamepad"
FM="$FLIP2_ROOT/pipeline/flipmouse"
API=30
TARGET=armv7a-linux-androideabi
NDK="${ANDROID_NDK_ROOT:-$HOME/.local/share/android-sdk/ndk/29.0.14206865}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$TOOLCHAIN" ]] || { echo "NDK not found at $NDK" >&2; exit 1; }
export PATH="$TOOLCHAIN/bin:$PATH"
BUILD="$GP/build"
FM_BUILD="$FM/build"

if [[ ! -f "$FM_BUILD/install/include/libevdev-1.0/libevdev/libevdev.h" ]]; then
  echo "libevdev not built — run: flip2 flipmouse build" >&2
  exit 1
fi

mkdir -p "$BUILD"
cd "$GP"
"$TOOLCHAIN/bin/clang" --target=$TARGET$API \
  -I"$FM_BUILD/install/include" -I"$FM_BUILD/install/include/libevdev-1.0" \
  -L"$FM_BUILD/install/lib" -o "$BUILD/gamepad" main.c -levdev
"$TOOLCHAIN/bin/llvm-strip" "$BUILD/gamepad"

rm -rf "$BUILD/bundle"
mkdir -p "$BUILD/bundle"
cp -r "$GP/properties/." "$BUILD/bundle/"
cp "$BUILD/gamepad" "$BUILD/bundle/"
(cd "$BUILD/bundle" && zip -r -FS "$BUILD/Flip2Gamepad.zip" . >/dev/null)
echo "Built: $BUILD/Flip2Gamepad.zip ($(wc -c <"$BUILD/Flip2Gamepad.zip" | tr -d ' ') bytes)"