#!/system/bin/sh
# Flip2: hardware OK -> vMouse left click. Listens on gpio_keys + matrix-keypad.
# Magisk: copy to /data/adb/service.d/flip2-vmouse-ok-click.sh (0755), reboot.

sleep 5

VMOUSE=/dev/input/event6
for e in /dev/input/event*; do
  getevent -lp "$e" 2>/dev/null | head -1 | grep -q 'vMouse' && VMOUSE="$e" && break
done
[ -e "$VMOUSE" ] || exit 0

click() {
  sendevent "$VMOUSE" 1 272 "$1"
  sendevent "$VMOUSE" 0 0 0
}

watch_gpio() {
  dev="$1"
  getevent "$dev" 2>/dev/null | while read -r _ type code val; do
    [ "$type" = 0001 ] || continue
    case "$val" in
      00000001|1) click 1 ;;
      00000000|0) click 0 ;;
    esac
  done
}

watch_matrix_ok() {
  dev="$1"
  getevent "$dev" 2>/dev/null | while read -r _ type code val; do
    [ "$type" = 0001 ] || continue
    case "$code" in
      0000001c|000001c|28|00000160|352)
        case "$val" in
          00000001|1) click 1 ;;
          00000000|0) click 0 ;;
        esac
        ;;
    esac
  done
}

for e in /dev/input/event*; do
  [ -e "$e" ] || continue
  lp=$(getevent -lp "$e" 2>/dev/null | head -3)
  echo "$lp" | grep -q gpio_keys && watch_gpio "$e" &
  echo "$lp" | grep -q matrix-keypad && watch_matrix_ok "$e" &
done

wait
