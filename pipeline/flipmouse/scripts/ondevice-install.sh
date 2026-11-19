#!/system/bin/sh
# Runs ON DEVICE as root (pushed by install.sh). Magisk 25.2 stages new
# modules in modules_update until reboot; unpack in place instead and start
# the supervised daemon now (service.sh does the same at boot).
MOD=/data/adb/modules/FlipMouse
pkill -f 'FlipMouse/service.sh' 2>/dev/null
killall mouse 2>/dev/null
pkill -9 -f '/FlipMouse/mouse' 2>/dev/null
i=0
while pidof mouse >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
  killall mouse 2>/dev/null
  sleep 0.25
  i=$((i + 1))
done
sleep 0.5
rm -f "$MOD/update"
TMP="$MOD/.mouse.new"
unzip -p /sdcard/Download/FlipMouse.zip mouse >"$TMP" 2>/dev/null || exit 1
chmod 755 "$TMP"
mv -f "$TMP" "$MOD/mouse"
unzip -o /sdcard/Download/FlipMouse.zip -d "$MOD/" -x mouse >/dev/null 2>&1 || true
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
