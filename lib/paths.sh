# shellcheck shell=bash
# Flip2 repo paths — source: source "$FLIP2_LIB/paths.sh" after setting FLIP2_LIB or from lib/
flip2_paths_init() {
  if [[ -z "${FLIP2_ROOT:-}" ]]; then
    local _lib
    _lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export FLIP2_ROOT="$(cd "$_lib/.." && pwd)"
  fi
  export FLIP2_OVERLAY="${FLIP2_OVERLAY:-$FLIP2_ROOT/launcher-overlay}"
  export FLIP2_PATCH="${FLIP2_PATCH:-$FLIP2_ROOT/launcher-patch}"
  export FLIP2_PIPELINE="${FLIP2_PIPELINE:-$FLIP2_ROOT/pipeline}"
  export FLIP2_LIB="${FLIP2_LIB:-$FLIP2_ROOT/lib}"
  export FLIP2_BIN="${FLIP2_BIN:-$FLIP2_ROOT/bin}"
}
flip2_paths_init
