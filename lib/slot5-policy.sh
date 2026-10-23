# shellcheck shell=bash
# TCL Launcher3: slot 5 / def_appmenu_position_five only safe for whitelisted packages on stock launcher.

FLIP2_SLOT5_DEFAULT="${FLIP2_SLOT5_DEFAULT:-com.android.music}"

flip2_slot5_whitelist() {
  echo "com.android.music myLatam myATT Media center"
}

flip2_slot5_is_whitelisted() {
  local pkg="$1"
  local w
  for w in $(flip2_slot5_whitelist); do
    [[ "$pkg" == "$w" ]] && return 0
  done
  return 1
}

flip2_slot5_can_hold() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 1
  case "$pkg" in
    @tools|tools|@string/tools_key) return 1 ;;
  esac
  flip2_slot5_is_whitelisted "$pkg"
}

flip2_slot5_effective_for_def_string() {
  local pkg="$1"
  if flip2_slot5_can_hold "$pkg"; then
    echo "$pkg"
  else
    echo "$FLIP2_SLOT5_DEFAULT"
  fi
}
