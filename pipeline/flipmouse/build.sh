#!/usr/bin/env bash
# Build FlipMouse (vendored + patched) for the Flip2:
#   armv7a static-libevdev binary -> Magisk module zip.
# Requires: NDK (ANDROID_NDK_ROOT or default), zip, wget.
# --debug: -DDEBUG build (logs to /cache/FlipMouse.log; use with `listen`).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FM="$FLIP2_ROOT/pipeline/flipmouse"
API=30
TARGET=armv7a-linux-androideabi
NDK="${ANDROID_NDK_ROOT:-$HOME/.local/share/android-sdk/ndk/29.0.14206865}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$TOOLCHAIN" ]] || { echo "NDK not found at $NDK" >&2; exit 1; }
DBG=""
[[ "${1:-}" == "--debug" ]] && DBG="-DDEBUG"
export PATH="$TOOLCHAIN/bin:$PATH"
BUILD="$FM/build"
mkdir -p "$BUILD"

# libevdev, built statically for armv7a (cached in build/)
if [[ ! -f "$BUILD/install/include/libevdev-1.0/libevdev/libevdev.h" ]]; then
  cd "$BUILD"
  [[ -f libevdev-1.13.2.tar.xz ]] || wget -nv https://www.freedesktop.org/software/libevdev/libevdev-1.13.2.tar.xz
  [[ -d libevdev-1.13.2 ]] || tar xf libevdev-1.13.2.tar.xz
  cd libevdev-1.13.2
  CC="$TOOLCHAIN/bin/clang --target=$TARGET$API" \
  AR="$TOOLCHAIN/bin/llvm-ar" RANLIB="$TOOLCHAIN/bin/llvm-ranlib" STRIP="$TOOLCHAIN/bin/llvm-strip" \
  ./configure --host=$TARGET --prefix="$BUILD/install" --disable-shared --enable-static \
    >/dev/null
  make -j"$(nproc)" >/dev/null
  make install >/dev/null
fi

cd "$FM"
"$TOOLCHAIN/bin/clang" --target=$TARGET$API \
  -I"$BUILD/install/include" -I"$BUILD/install/include/libevdev-1.0" \
  -L"$BUILD/install/lib" -o "$BUILD/mouse" main.c -levdev $DBG
"$TOOLCHAIN/bin/llvm-strip" "$BUILD/mouse"

rm -rf "$BUILD/bundle"; mkdir -p "$BUILD/bundle"
cp -r "$FM/properties/." "$BUILD/bundle/"
cp "$BUILD/mouse" "$BUILD/bundle/"
(cd "$BUILD/bundle" && zip -r -FS "$BUILD/FlipMouse.zip" . >/dev/null)
echo "Built: $BUILD/FlipMouse.zip ($(wc -c <"$BUILD/FlipMouse.zip" | tr -d ' ') bytes)"
