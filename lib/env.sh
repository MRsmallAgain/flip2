# shellcheck shell=bash
# JDK + Android SDK PATH for apktool, zipalign, apksigner.
flip2_env_init() {
  export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}"
  export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/build-tools/34.0.0:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$HOME/.local/bin:$PATH"
  export ANDROID_DEBUG_KEY="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"
}

flip2_require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null || { echo "Missing command: $c" >&2; return 1; }
  done
}
