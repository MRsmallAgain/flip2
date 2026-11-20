#!/system/bin/sh
# flip2burnMouse boot service (Magisk late_start).
MOD=${0%/*}
LOG=/cache/flip2burnMouse.log

[ -x "$MOD/mouse" ] || MOD=/data/adb/modules/flip2burnMouse
[ -x "$MOD/mouse" ] || exit 0

echo "$(date) service.sh start (module=$MOD)" >>"$LOG"

if [ ! -f /data/local/flip2/gamepad.conf ]; then
  mkdir -p /data/local/flip2
  cat > /data/local/flip2/gamepad.conf <<'EOF'
landscape_auto=1
enabled=0
# block_cursor_toggle_packages=com.dozingcatsoftware.bouncy
# portrait_gamepad_packages=com.shatteredpixel.shatteredpixeldungeon
# portrait_sdl_pointer_packages=org.scummvm.scummvm
EOF
fi

i=0
while [ ! -e /dev/input/event2 ] && [ "$i" -lt 30 ]; do
    sleep 0.5
    i=$((i + 1))
done

if [ -z "$(pidof mouse)" ]; then
    (
        while true; do
            if [ -z "$(pidof mouse)" ]; then
                echo "$(date) starting mouse" >>"$LOG"
                "$MOD/mouse" </dev/null >>"$LOG" 2>&1
                echo "$(date) mouse exited ($?)" >>"$LOG"
            fi
            sleep 15
        done
    ) </dev/null >>"$LOG" 2>&1 &
fi
