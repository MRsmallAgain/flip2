# Fork module — boot loop / "System is starting"

If the phone hangs on **System is starting** or Launcher3 crashes in a loop after **`flip2 fork install`**, disable module **`flip2_launcher3_fork`** and reboot.

## On the phone

1. **Power off** (hold Power ~15–20 s).
2. **Power on** → hold **Volume Down** from the logo until boot completes (Magisk safe mode: modules off for one boot).
3. **Magisk** → **Modules** → remove **Flip2 Launcher3 fork** → **Reboot**.

See also [launcher-patch/EMERGENCY-unresponsive.md](../launcher-patch/EMERGENCY-unresponsive.md).

## adb

```bash
flip2 fork rollback
```

## After recovery

- Use **RRO overlay only**: `flip2 apply`, `flip2 swap` (slot 5 guarded on stock).
- Debug-signed whole-Launcher3 Magisk replace **failed on Gflip6** (same as withdrawn `flip2_launcher3_null_icon_fix`).
