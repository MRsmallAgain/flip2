#!/usr/bin/env bash
# Stable APK basename for installer payload/apks/, apks.txt, and wizard incoming/.
# Sourced by emit.sh, pack-installer.sh, and pipeline/wizard/gen-pipeline-js.sh.
# Pass MANIFEST as second arg for manifest .incoming fallback.
# Safe to source from other scripts (no top-level set -e/-u).

wizard_apk_basename() {
  local name="${1:-}"
  local manifest="${2:-}"
  case "$name" in
    forkgram) printf '%s\n' forkgram.apk ;;
    materialfiles) printf '%s\n' materialfiles.apk ;;
    launcher4) printf '%s\n' launcher4.apk ;;
    ime) printf '%s\n' nullkeyboard.apk ;;
    intertune) printf '%s\n' intertune.apk ;;
    bouncy) printf '%s\n' bouncy.apk ;;
    astro_loop) printf '%s\n' astro-loop.apk ;;
    *)
      if [[ -n "$manifest" && -f "$manifest" ]]; then
        jq -r --arg n "$name" '.components[] | select(.name==$n) | .incoming // empty' "$manifest"
      else
        printf '%s\n' ''
      fi
      ;;
  esac
}

