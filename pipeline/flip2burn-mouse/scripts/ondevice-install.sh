#!/system/bin/sh
# Runs ON DEVICE as root (pushed by install.sh).
MOD=/data/adb/modules/flip2burnMouse
pkill -f 'flip2burnMouse/service.sh' 2>/dev/null
pkill -f 'FlipMouseArcade/service.sh' 2>/dev/null
pkill -f 'FlipMouse/service.sh' 2>/dev/null
killall mouse 2>/dev/null
pkill -9 -f '/flip2burnMouse/mouse' 2>/dev/null
pkill -9 -f '/FlipMouseArcade/mouse' 2>/dev/null
pkill -9 -f '/FlipMouse/mouse' 2>/dev/null
i=0
while pidof mouse >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
  killall mouse 2>/dev/null
  sleep 0.25
  i=$((i + 1))
done
sleep 0.5
rm -rf /data/adb/modules/FlipMouse /data/adb/modules/FlipMouseArcade
rm -f "$MOD/update"
TMP="$MOD/.mouse.new"
unzip -p /sdcard/Download/flip2burnMouse.zip mouse >"$TMP" 2>/dev/null || exit 1
chmod 755 "$TMP"
mv -f "$TMP" "$MOD/mouse"
unzip -o /sdcard/Download/flip2burnMouse.zip -d "$MOD/" -x mouse >/dev/null 2>&1 || true
chmod 755 "$MOD/mouse" "$MOD/service.sh"
chmod 644 "$MOD/module.prop"
rm -f /cache/flip2burnMouse.log /cache/FlipMouseArcade.log /cache/FlipMouse.log
nohup sh "$MOD/service.sh" </dev/null >/dev/null 2>&1 &
sleep 2
echo ---MODULE---
ls "$MOD"
echo ---PROC---
pgrep -a mouse
echo ---LOG---
cat /cache/flip2burnMouse.log 2>/dev/null
