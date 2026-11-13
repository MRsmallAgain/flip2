#!/usr/bin/env bash
# Install the local pre-commit gate hook.
#
# Run once per clone:  bash pipeline/ci/install-hooks.sh
#
# Why this exists: .gitlab-ci.yml runs the same gates (pipeline/ci/gates.sh),
# but GitLab withholds CI jobs on this account until identity verification is
# done, so the pipeline cannot enforce anything yet. A local hook is the only
# enforcement available until that clears -- and it stays useful afterwards,
# since it catches a broken script before the commit even exists.
#
# The gates are ~3s, so there is no file-type filtering: a gate that skips
# itself on a "docs-only" commit is a gate that misses a JSON edit under docs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-commit"

[[ -d "$ROOT/.git" ]] || { echo "not a git checkout: $ROOT" >&2; exit 1; }

if [[ -e "$HOOK" && ! -f "${HOOK}.flip2" ]]; then
  # Someone else's hook. Refusing beats silently replacing it -- the user loses a
  # hook they may depend on and has no easy way to notice.
  echo "refusing to overwrite an existing hook: $HOOK" >&2
  echo "move it aside, or add 'bash pipeline/ci/gates.sh' to it yourself" >&2
  exit 1
fi

cat > "$HOOK" <<'HOOKEOF'
#!/usr/bin/env bash
# Installed by pipeline/ci/install-hooks.sh -- re-run that to update.
# Bypass for a WIP commit with: git commit --no-verify
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
if ! out="$(bash "$root/pipeline/ci/gates.sh" 2>&1)"; then
  printf '%s\n' "$out" >&2
  echo >&2
  echo "pre-commit: device-free gates failed (see above)." >&2
  echo "pre-commit: fix them, or bypass once with: git commit --no-verify" >&2
  exit 1
fi
HOOKEOF

chmod +x "$HOOK"
touch "${HOOK}.flip2"
echo "installed: $HOOK"
echo "the gates now run before every commit (~3s); bypass with --no-verify"
