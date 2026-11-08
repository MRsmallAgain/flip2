#!/system/bin/sh
MOD=/data/adb/modules/FlipMouseArcade
pkill -f 'FlipMouseArcade/service.sh' 2>/dev/null
pkill -f 'FlipMouseArcade/mouse' 2>/dev/null
pkill -f 'FlipMouse/service.sh' 2>/dev/null
pkill -f 'FlipMouse/mouse' 2>/dev/null
rm -rf /data/adb/modules/FlipMouse
sleep 1
rm -f "$MOD/update"
unzip -o /sdcard/Download/FlipMouseArcade.zip -d "$MOD/" >/dev/null
chmod 755 "$MOD/mouse"
chmod 755 "$MOD/service.sh"
chmod 644 "$MOD/module.prop"
rm -f /cache/FlipMouseArcade.log
nohup sh "$MOD/service.sh" </dev/null >/dev/null 2>&1 &
sleep 2
echo ---MODULE---
ls "$MOD"
echo ---PROC---
pgrep -a mouse
echo ---LOG---
cat /cache/FlipMouseArcade.log 2>/dev/null
