#!/system/bin/sh
# FlipMouse Arcade boot service (Magisk late_start).
# Single daemon: gamepad + landscape cursor + portrait mouse modes.
MOD=${0%/*}
LOG=/cache/FlipMouseArcade.log

[ -x "$MOD/mouse" ] || MOD=/data/adb/modules/FlipMouseArcade
[ -x "$MOD/mouse" ] || exit 0

echo "$(date) service.sh start (module=$MOD)" >>"$LOG"

if [ ! -f /data/local/flip2/gamepad.conf ]; then
  mkdir -p /data/local/flip2
  printf 'landscape_auto=1\nenabled=0\n' > /data/local/flip2/gamepad.conf
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
