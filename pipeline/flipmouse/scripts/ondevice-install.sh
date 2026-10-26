#!/system/bin/sh
# Runs ON DEVICE as root (pushed by install.sh). Magisk 25.2 stages new
# modules in modules_update until reboot; unpack in place instead and start
# the supervised daemon now (service.sh does the same at boot).
MOD=/data/adb/modules/FlipMouse
pkill -f 'FlipMouse/service.sh' 2>/dev/null
pkill -f 'FlipMouse/mouse' 2>/dev/null
sleep 1
rm -f "$MOD/update"
unzip -o /sdcard/Download/FlipMouse.zip -d "$MOD/" >/dev/null
chmod 755 "$MOD/mouse"
chmod 755 "$MOD/service.sh"
chmod 644 "$MOD/module.prop"
rm -f /cache/FlipMouse.log
nohup sh "$MOD/service.sh" </dev/null >/dev/null 2>&1 &
sleep 2
echo ---MODULE---
ls "$MOD"
echo ---PROC---
pgrep -a mouse
echo ---LOG---
cat /cache/FlipMouse.log 2>/dev/null
