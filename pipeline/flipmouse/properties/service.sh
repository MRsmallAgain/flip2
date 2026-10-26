#!/system/bin/sh
# FlipMouse boot service (Magisk late_start).
#
# The daemon is a passive observer until the soft-key toggle, so it is safe to
# keep it running all the time. Keep it detached from any adb/init pipe and
# supervise it: native processes started from an adb shell can disappear when
# that shell's session is cleaned up, and an accidental crash should not cost
# the mouse until the next reboot.
MOD=${0%/*}
LOG=/cache/FlipMouse.log

[ -x "$MOD/mouse" ] || MOD=/data/adb/modules/FlipMouse
[ -x "$MOD/mouse" ] || exit 0

echo "$(date) service.sh start (module=$MOD)" >>"$LOG"

# Input devices may appear slightly after late_start; wait for the matrix keypad.
i=0
while [ ! -e /dev/input/event2 ] && [ "$i" -lt 30 ]; do
    sleep 0.5
    i=$((i + 1))
done

# One supervisor only. It stays in the background, detached from stdio, and
# restarts the daemon if it ever exits.
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
