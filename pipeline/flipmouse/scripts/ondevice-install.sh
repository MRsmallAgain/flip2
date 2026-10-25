#!/system/bin/sh
# Runs ON DEVICE as root (pushed by install.sh). Magisk 25.2 stages new
# modules in modules_update until reboot; unpack in place instead and start
# the daemon now (service.sh does the same at boot).
MOD=/data/adb/modules/FlipMouse
pkill -f FlipMouse/mouse 2>/dev/null
rm -f "$MOD/update"
unzip -o /sdcard/Download/FlipMouse.zip -d "$MOD/" >/dev/null
chmod 755 "$MOD/mouse"
chmod 644 "$MOD/module.prop"
rm -f /cache/FlipMouse.log
nohup "$MOD/mouse" </dev/null >/dev/null 2>&1 &
sleep 2
echo ---MODULE---
ls "$MOD"
echo ---PROC---
pgrep -a mouse
