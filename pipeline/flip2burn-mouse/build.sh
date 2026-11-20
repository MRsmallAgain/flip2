#!/usr/bin/env bash
# Build flip2burnMouse (gamepad + landscape cursor + portrait mouse + star IME handoff)
# -> Magisk flip2burnMouse.zip
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FM="$FLIP2_ROOT/pipeline/flip2burn-mouse"
API=30
TARGET=armv7a-linux-androideabi
NDK="${ANDROID_NDK_ROOT:-$HOME/.local/share/android-sdk/ndk/29.0.14206865}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$TOOLCHAIN" ]] || { echo "NDK not found at $NDK" >&2; exit 1; }
DBG=""
[[ "${1:-}" == "--debug" ]] && DBG="-DDEBUG"
export PATH="$TOOLCHAIN/bin:$PATH"
BUILD="$FM/build"
LEVDEV="$BUILD/libevdev-install"
mkdir -p "$BUILD"

if [[ ! -f "$LEVDEV/include/libevdev-1.0/libevdev/libevdev.h" ]]; then
  LEVDEV_SRC="$BUILD/libevdev"
  mkdir -p "$LEVDEV_SRC"
  cd "$LEVDEV_SRC"
  [[ -f libevdev-1.13.2.tar.xz ]] || wget -nv https://www.freedesktop.org/software/libevdev/libevdev-1.13.2.tar.xz
  [[ -d libevdev-1.13.2 ]] || tar xf libevdev-1.13.2.tar.xz
  cd libevdev-1.13.2
  CC="$TOOLCHAIN/bin/clang --target=$TARGET$API" \
  AR="$TOOLCHAIN/bin/llvm-ar" RANLIB="$TOOLCHAIN/bin/llvm-ranlib" STRIP="$TOOLCHAIN/bin/llvm-strip" \
  ./configure --host=$TARGET --prefix="$LEVDEV" --disable-shared --enable-static \
    >/dev/null
  make -j"$(nproc)" >/dev/null
  make install >/dev/null
fi

cd "$FM"
"$TOOLCHAIN/bin/clang" --target=$TARGET$API \
  -I"$LEVDEV/include" -I"$LEVDEV/include/libevdev-1.0" \
  -L"$LEVDEV/lib" -o "$BUILD/mouse" main.c -levdev $DBG
"$TOOLCHAIN/bin/llvm-strip" "$BUILD/mouse"

rm -rf "$BUILD/bundle"
mkdir -p "$BUILD/bundle"
cp -r "$FM/properties/." "$BUILD/bundle/"
cp "$BUILD/mouse" "$BUILD/bundle/"
(cd "$BUILD/bundle" && zip -r -FS "$BUILD/flip2burnMouse.zip" . >/dev/null)
echo "Built: $BUILD/flip2burnMouse.zip ($(wc -c <"$BUILD/flip2burnMouse.zip" | tr -d ' ') bytes)"
