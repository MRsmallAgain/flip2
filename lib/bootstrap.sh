# shellcheck shell=bash
# Source all flip2 libs. Usage: source "$FLIP2_ROOT/lib/bootstrap.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "$SCRIPT_DIR/paths.sh"
# shellcheck source=constants.sh
source "$SCRIPT_DIR/constants.sh"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"
# shellcheck source=adb.sh
source "$SCRIPT_DIR/adb.sh"
# shellcheck source=magisk.sh
source "$SCRIPT_DIR/magisk.sh"
# shellcheck source=sign.sh
source "$SCRIPT_DIR/sign.sh"
# shellcheck source=slot5-policy.sh
source "$SCRIPT_DIR/slot5-policy.sh"
