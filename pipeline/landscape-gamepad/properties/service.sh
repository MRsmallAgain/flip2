#!/system/bin/sh
MOD=${0%/*}
LOG=/cache/Flip2Gamepad.log

[ -x "$MOD/gamepad" ] || MOD=/data/adb/modules/Flip2Gamepad
[ -x "$MOD/gamepad" ] || exit 0

mkdir -p /data/local/flip2
if [ ! -f /data/local/flip2/gamepad.conf ]; then
  echo "landscape_auto=1" > /data/local/flip2/gamepad.conf
  echo "enabled=0" >> /data/local/flip2/gamepad.conf
  chmod 0664 /data/local/flip2/gamepad.conf 2>/dev/null
fi

echo "$(date) Flip2Gamepad service start" >>"$LOG"

i=0
while [ ! -e /dev/input/event2 ] && [ "$i" -lt 30 ]; do
  sleep 0.5
  i=$((i + 1))
done

if [ -z "$(pidof gamepad)" ]; then
  (
    while true; do
      if [ -z "$(pidof gamepad)" ]; then
        echo "$(date) starting gamepad" >>"$LOG"
        "$MOD/gamepad" </dev/null >>"$LOG" 2>&1
        echo "$(date) gamepad exited ($?)" >>"$LOG"
      fi
      sleep 15
    done
  ) </dev/null >>"$LOG" 2>&1 &
fi
