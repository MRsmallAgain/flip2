#!/system/bin/sh
MOD=/data/adb/modules/Flip2Gamepad
pkill -f 'Flip2Gamepad/service.sh' 2>/dev/null
pkill -f 'Flip2Gamepad/gamepad' 2>/dev/null
pkill gamepad 2>/dev/null
sleep 1
rm -f "$MOD/update"
unzip -o /sdcard/Download/Flip2Gamepad.zip -d "$MOD/" >/dev/null
chmod 755 "$MOD/gamepad"
chmod 755 "$MOD/service.sh"
chmod 644 "$MOD/module.prop"
mkdir -p /data/local/flip2
rm -f /cache/Flip2Gamepad.log
nohup sh "$MOD/service.sh" </dev/null >/dev/null 2>&1 &
sleep 2
echo ---MODULE---
ls "$MOD"
echo ---PROC---
pgrep -a gamepad
echo ---CONF---
cat /data/local/flip2/gamepad.conf 2>/dev/null
