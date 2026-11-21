#!/usr/bin/env bash
# Device-free gates. Run by .gitlab-ci.yml on every push, and runnable by hand:
#
#   bash pipeline/ci/gates.sh
#
# Deliberately limited to checks that need no phone, no adb, no AWS credentials,
# no packed dist/ artefacts and no network. A gate that fails for environmental
# reasons teaches people to ignore the pipeline, which is worse than not having
# one. Everything here was confirmed to pass on a fresh clone before it was
# added — the clean clone is the closest thing to a runner this repo has.
#
# Not included on purpose: shellcheck (129 scripts, unverified baseline — a red
# pipeline from day one would be noise), and anything that runs `flip2 release`,
# which needs both dist/ and a real remote.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
section() { printf '\n== %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

# --- tooling ---------------------------------------------------------------
# Fail loudly rather than skipping: a missing tool in the image means the gate
# silently stopped covering anything.
for t in git jq node bash; do
  command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 2; }
done

# --- 1. shell syntax -------------------------------------------------------
# bin/flip2 and the Magisk update-binary scripts are bash without a .sh suffix,
# and a syntax error there is a bricked installer, so they are covered too.
section "shell syntax (bash -n)"
mapfile -t shells < <(
  {
    git ls-files '*.sh'
    echo bin/flip2
    git ls-files '*update-binary'
  } | sort -u
)
for f in "${shells[@]}"; do
  [[ -f "$f" ]] || continue
  out="$(bash -n "$f" 2>&1)" || { bad "$f"; printf '%s\n' "$out" | head -5; }
done
printf '      %d script(s) parsed\n' "${#shells[@]}"

# --- 2. JavaScript syntax --------------------------------------------------
# The wizard and Companion modules are ES modules, so `node --check <file>`
# (CommonJS) rejects their valid `import`/`export` — the input-type flag is what
# makes this a real check rather than a false pass.
section "JavaScript syntax (node --check, ES modules)"
mapfile -t js < <(git ls-files '*.js')
for f in "${js[@]}"; do
  out="$(node --input-type=module --check < "$f" 2>&1)" || { bad "$f"; printf '%s\n' "$out" | head -5; }
done
printf '      %d file(s) parsed\n' "${#js[@]}"

# --- 3. JSON validity ------------------------------------------------------
# catalog.json drives every download pin, so a trailing comma there is a broken
# wizard, not a lint nit.
section "JSON validity (jq)"
mapfile -t json < <(git ls-files '*.json')
for f in "${json[@]}"; do
  jq -e . "$f" >/dev/null 2>&1 || bad "$f (invalid JSON)"
done
printf '      %d file(s) parsed\n' "${#json[@]}"

# --- 4. generated artefacts match their generators -------------------------
# install.sh/verify.sh and the two device-paths.js bundles are generated from
# pipeline/wizard/device-paths.json. A hand-edit to one side ships a wizard that
# installs to paths the phone does not use.
section "generated wizard artefacts (no drift)"
./bin/flip2 wizard check || bad "wizard check reported drift (run: flip2 wizard render)"
./bin/flip2 wizard pins --check || bad "pins.json is stale (run: flip2 wizard pins)"

# --- 5. profiles.json component ids vs Companion PROFILE_IDS ---------------
# Missing ids cause "profile.list rejected" on Arcade/Messaging Apply.
section "profile component ids vs PROFILE_IDS"
bash "$ROOT/pipeline/ci/gate-profile-ids.sh" || bad "profile ids gate failed (see pipeline/ci/gate-profile-ids.sh)"

# --- 6. catalog installer pins match dist/ (when zips exist) ---------------
# Repacks often keep the same byte count; only SHA catches stale pins or stale cache.
section "catalog installer pins vs dist"
DIST="$ROOT/pipeline/deploy/dist"
for id in installer-full installer-slim installer-base; do
  f="$(jq -r --arg id "$id" '.files[] | select(.id==$id) | .file' "$ROOT/wizard/catalog.json" 2>/dev/null)"
  exp="$(jq -r --arg id "$id" '.files[] | select(.id==$id) | .sha256' "$ROOT/wizard/catalog.json" 2>/dev/null)"
  [[ -n "$f" && "$f" != null && -n "$exp" && "$exp" != null ]] || continue
  zip="$DIST/$f"
  [[ -f "$zip" ]] || continue
  got="$(sha256sum "$zip" | awk '{print $1}')"
  [[ "$got" == "$exp" ]] || bad "catalog $id sha256 mismatch (repack? run flip2 installer pack + update catalog + flip2 wizard pins)"
done

# --- verdict ---------------------------------------------------------------
echo
if [[ "$fail" -ne 0 ]]; then
  echo "FAILED — see the lines above"
  exit 1
fi
echo "OK: all device-free gates passed"
