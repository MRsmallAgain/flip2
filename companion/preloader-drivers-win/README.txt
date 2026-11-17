Preloader / mtkclient helpers (Windows)
=============================================

Bundled with TCL Flip2 Manager for the rooting step (MTK preloader 0e8d:2000).

1. UsbDk (UsbDk_1.0.22_x64.msi)
   Optional but recommended for mtkclient and some USB access patterns.
   In the app: Rooting → Install UsbDk, or double-click the MSI (admin).

2. MediaTek USB VCOM driver (NOT bundled)
   Companion auto-connects to the preloader over a serial COM port. On Windows
   that port only appears after the MediaTek USB VCOM driver is installed.

   Typical steps:
   - Download MediaTek SP Flash Tool or the official VCOM driver package from
     MediaTek / your device vendor (not redistributed in this app).
   - Device Manager → update driver for the unknown MTK device (0e8d:2000)
     or "Install from disk" using the vendor .inf.

   Google USB Driver (adb) does NOT provide VCOM — it is separate from adb.

3. Google platform-tools
   Bundled separately under resources\platform-tools\ (adb for Prepare).

After installing VCOM: unplug USB, remove/reinsert battery, replug USB, then
Start watching again in the rooting step.
