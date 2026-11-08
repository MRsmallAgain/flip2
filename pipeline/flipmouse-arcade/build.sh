#!/usr/bin/env bash
# Build FlipMouse Arcade (gamepad + mouse single daemon) -> Magisk FlipMouseArcade.zip
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FA="$FLIP2_ROOT/pipeline/flipmouse-arcade"
FM_BUILD="$FLIP2_ROOT/pipeline/flipmouse/build"
API=30
TARGET=armv7a-linux-androideabi
NDK="${ANDROID_NDK_ROOT:-$HOME/.local/share/android-sdk/ndk/29.0.14206865}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$TOOLCHAIN" ]] || { echo "NDK not found at $NDK" >&2; exit 1; }
DBG=""
[[ "${1:-}" == "--debug" ]] && DBG="-DDEBUG"
export PATH="$TOOLCHAIN/bin:$PATH"
BUILD="$FA/build"
mkdir -p "$BUILD"

[[ -f "$FM_BUILD/install/include/libevdev-1.0/libevdev/libevdev.h" ]] || {
  echo "libevdev not built — run: flip2 flipmouse build" >&2
  exit 1
}

cd "$FA"
"$TOOLCHAIN/bin/clang" --target=$TARGET$API \
  -I"$FM_BUILD/install/include" -I"$FM_BUILD/install/include/libevdev-1.0" \
  -L"$FM_BUILD/install/lib" -o "$BUILD/mouse" main.c -levdev $DBG
"$TOOLCHAIN/bin/llvm-strip" "$BUILD/mouse"

rm -rf "$BUILD/bundle"
mkdir -p "$BUILD/bundle"
cp -r "$FA/properties/." "$BUILD/bundle/"
cp "$BUILD/mouse" "$BUILD/bundle/"
(cd "$BUILD/bundle" && zip -r -FS "$BUILD/FlipMouseArcade.zip" . >/dev/null)
echo "Built: $BUILD/FlipMouseArcade.zip ($(wc -c <"$BUILD/FlipMouseArcade.zip" | tr -d ' ') bytes)"
