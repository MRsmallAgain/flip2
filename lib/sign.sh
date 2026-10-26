# shellcheck shell=bash
# APK signing helpers — require flip2_env_init first (ANDROID_SDK_ROOT, ANDROID_DEBUG_KEY).

flip2_sign_find_tool() {
  # $1 = tool name (zipalign | apksigner). Honors explicit override var.
  local tool="$1"
  local override="${tool^^}" p
  override="${override//-/_}"
  if [[ -n "${!override:-}" && -x "${!override}" ]]; then
    echo "${!override}"
    return 0
  fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]] && [[ -x "$ANDROID_SDK_ROOT/build-tools/$tool" ]]; then
    echo "$ANDROID_SDK_ROOT/build-tools/$tool"
    return 0
  fi
  for p in "${ANDROID_SDK_ROOT:-/nonexistent}"/build-tools/*/"$tool"; do
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  command -v "$tool" 2>/dev/null
}

flip2_sign_ensure_keystore() {
  local key="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"
  if [[ ! -f "$key" ]]; then
    echo "Creating debug keystore at $key"
    mkdir -p "$(dirname "$key")"
    keytool -genkey -v -keystore "$key" -storepass android -alias androiddebugkey \
      -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
      -dname 'CN=Android Debug,O=Android,C=US' >/dev/null
  fi
  echo "$key"
}

# flip2_sign_apk <unsigned.apk> <aligned.apk> <signed.apk>
flip2_sign_apk() {
  local unsigned="$1" aligned="$2" signed="$3" zipalign apksigner key
  zipalign="$(flip2_sign_find_tool zipalign)" || true
  apksigner="$(flip2_sign_find_tool apksigner)" || true
  [[ -n "${zipalign:-}" && -x "${zipalign:-}" ]] || { echo "zipalign not found (set ANDROID_SDK_ROOT)" >&2; return 1; }
  [[ -n "${apksigner:-}" && -x "${apksigner:-}" ]] || { echo "apksigner not found (set ANDROID_SDK_ROOT)" >&2; return 1; }
  key="$(flip2_sign_ensure_keystore)" || return 1
  "$zipalign" -p -f 4 "$unsigned" "$aligned"
  "$apksigner" sign --ks "$key" --ks-pass pass:android --key-pass pass:android \
    --out "$signed" "$aligned"
}
