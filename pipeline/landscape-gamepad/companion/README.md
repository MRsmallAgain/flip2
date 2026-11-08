# Gamepad companion APK (`com.tim.flip2.gamepad`)

Settings UI for the Magisk **Flip2Gamepad** daemon. Root is not required for the APK itself; it only needs permission to write `/data/local/flip2/gamepad.conf` (same pattern as profile.list — typically via a "Apply" button that runs `su`, or pre-created file from Magisk `service.sh`).

## Planned UI

- **Preset:** Dual-stick (default) / D-pad-only
- **Landscape auto:** `landscape_auto=1`
- **Force on:** `enabled=1`

## Config format

```ini
landscape_auto=1
enabled=0
```

Until companion-build exists:

```sh
adb shell su -c 'mkdir -p /data/local/flip2 && printf "landscape_auto=1\nenabled=0\n" > /data/local/flip2/gamepad.conf'
```
