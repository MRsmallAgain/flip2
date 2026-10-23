#!/system/bin/sh
# Ensure priv-app permissions
chmod 644 /system/priv-app/Launcher3/Launcher3.apk 2>/dev/null
chown root:root /system/priv-app/Launcher3/Launcher3.apk 2>/dev/null
