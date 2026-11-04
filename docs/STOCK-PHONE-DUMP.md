# Stock phone firmware dump (4058G)

Use a **factory/stock** unit (e.g. UPBO / `4058G-2AWFUS1`) as the **authoritative** firmware source for:

- Restoring a bootlooping daily driver (**ONTK…**) via SP Flash or fastbootd
- Future **`flip2 image merge-super --stock-super`** (must be **this** phone’s readback, not donor MRV8…)

**Do not** treat donor `~/flip2-backups/donor-image-2026-10-28/` as the daily driver’s stock.

## Before you dump

1. Record sticker: **model**, **SKU** (e.g. `4058G-2AWFUS1`), **IMEI**, **UPBO/UPEJ**, hardware rev (GFLIP5… dates).
2. If Android boots: `adb shell getprop ro.build.fingerprint ro.serialno` → save in `RUN-REPORT.md`.
3. Create output dir:
   ```bash
   STOCK=~/flip2-backups/stock-$(date +%F)-SERIAL
   mkdir -p "$STOCK"
   ```

## Method A — SP Flash Tool readback (preferred, no root)

1. Same **scatter** as your MT6739 4058G package (must match this hardware).
2. Phone **power off**, USB, enter **download mode** (wiki / preloader — not normal adb).
3. SP Flash: **Readback** tab (not Download).
4. Select scatter; read back at minimum:
   - **super** (critical, ~2 GiB)
   - **boot**, **recovery**, **dtbo**
   - **vbmeta**, **vbmeta_system**, **vbmeta_vendor**
5. **Do not read/write EMMC_BOOT / preloader** unless you accept brick risk.
6. Copy readback images into `$STOCK/`; note SP Flash’s default output folder.
7. On host:
   ```bash
   cd "$STOCK"
   sha256sum *.img | tee SHA256SUMS.txt
   ```

## Method B — fastbootd fetch (if device supports it)

Daily ONTK did **not** support `fastboot fetch`. Try on **stock** phone if you unlock for testing:

```bash
fastboot reboot fastboot
fastboot fetch super super.img
fastboot fetch boot boot.img
fastboot fetch vbmeta_system vbmeta_system.img
# … vbmeta, vbmeta_vendor, dtbo, recovery
```

If fetch fails, use Method A or C.

## Method C — adb + root `dd` (only if stock is rooted — usually not)

For **super**, hash **on device** (never raw `adb pull` of full dd stream — CRLF corrupts hash). See IMAGE-BUILD.md recovery section:

```bash
adb shell 'su -c "dd if=/dev/block/by-name/super bs=4096 count=412577 2>/dev/null | sha256sum"'
# Pull only via SP Flash or fastboot fetch; dd-to-sdcard then pull is OK if su exists
```

Stock phones are usually **not** rooted — use **Method A**.

## Method D — Wizard boot backup (boot only)

Companion **Save boot copy** → `~/Downloads/flip2-wizard/backups/` + JSON sidecar (**serial** must match stock phone). Does **not** dump `super`; still do Method A for merge/restore.

## After dump

| File | Use |
|------|-----|
| `super.img` | Restore ONTK; `flip2 image merge-super --stock-super` |
| `vbmeta*.img` | Restore chain with stock super |
| `boot.img` | Optional; ONTK may use neutron after restore |

Document in `$STOCK/RUN-REPORT.md`: serial, fingerprint, sha256 table, method (SP Flash readback).

## Restore ONTK from stock dump

1. ONTK in **download mode** or **fastbootd** per partition.
2. SP Flash **Download** with **stock readback images** (or fastboot flash super/boot/vbmeta from `$STOCK`).
3. **Uncheck preloader** on first restore unless package requires it.
4. After boot: save **ONTK** boot backup; flip2 via Magisk **full** installer — no custom super until merge uses **stock UPBO super.img**.
