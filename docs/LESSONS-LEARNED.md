# Flip2 lessons learned (human + agent)

Operational knowledge from **4058G / Gflip6** work (donor MRV8, daily driver ONTK, stock UPBO readback unit RWORP), November 2026. Treat every incident as **input to the pipeline**, not a one-off chat fix.

**Ops hub (raw logs):** `~/flip2-backups/stock-UPBO-2026-11-02/` — forensics, scripts, flash logs. **Canonical behavior** lives in this repo under `docs/` and `pipeline/`.

---

## Doctrine (read first)

1. **Every session teaches something.** If we improvised successfully once, capture it as a **script stage**, a **gate**, or a **doc section** before closing the task.
2. **Prefer pipeline-driven execution:** `flip2` CLI → `pipeline/<domain>/*.sh` → logged steps with **PASS/FAIL** or explicit **verify gates**. Avoid ad-hoc one-liners on a daily driver unless they are a deliberate experiment with a written rollback.
3. **Gated recursion and validity testing:**
   - **Gate** — typed words (`erase`, `factory`), health checks (`product`, `serialno`, `partition-size`), SHA-256 + size pins (`catalog.json`, `verify-dump.sh`), or “Android stable + adb authorized” before destructive steps.
   - **Recursion** — prove on **expendable hardware** (donor drill in [FACTORY-TEST.md](FACTORY-TEST.md)), then promote the **same script** to the daily driver with serial checks in the script.
   - **Validity** — after each stage: `verify.sh`, `sha256sum`, `probe-fastboot-mode.sh`, or manifest `MANIFEST.json`; **do not** assume success from a green UI line alone ([WIZARD-FAILURES.md](WIZARD-FAILURES.md)).
4. **One writer on the phone.** Never run two host scripts that both `adb reboot bootloader`, autoboot loops, or `fastboot reboot` while the user is authorizing USB — it causes immediate reboot loops ([Host automation vs user adb](#host-automation-vs-user-adb)).

Agents: full rules in [AGENT-OPERATING-DOCTRINE.md](AGENT-OPERATING-DOCTRINE.md) and [AGENTS.md](../AGENTS.md).

---

## Backup and userdata

| Lesson | Detail |
|--------|--------|
| **Backup before wipe is not optional on the daily driver** | ONTK had **no** completed app/userdata export before lab flashes and optional factory reset. Host only has **0-byte** `fastboot fetch` placeholders in `~/flip2-backups/daily-ONTKKB9L7PEUX4Z5-2026-11-02/`. |
| **Donor ≠ daily driver** | Rich pre-wipe bundle is **`MRV8IJJVPRYTS4UG`**: `~/flip2-backups/pre-wipe-2026-10-29T03-48/` and `~/flip2-pre-wipe-backup/` (contacts, SMS, media, `user-packages.txt`). Do not restore that PIM as ONTK’s without checking serial in `MANIFEST.json`. |
| **Full userdata needs metadata** | FBE: `userdata.img` without matching `metadata.img` is useless. Plaintext **`readable/`** exports survive wipe regardless. |
| **`adb exec-out su dd` trap** | `su` on a pty corrupts binary streams (CR/LF). Use `stty -opost` in the remote command or stage to `/sdcard` then `adb pull`. |
| **fastboot fetch** | **Not supported** on ONTK (bootloader or fastbootd). Stock UPBO readback = **SP Flash Readback** ([STOCK-PHONE-DUMP.md](STOCK-PHONE-DUMP.md), `~/flip2-backups/stock-UPBO-2026-11-02/WINDOWS-READBACK.md`). |
| **Pipeline gap (to close)** | Add `flip2 backup export` (or documented `pipeline/backup/export.sh`) run **before** any wipe-gated slice or custom super flash; gate flash scripts on `MANIFEST.json` present for **target serial**. |

---

## Firmware identity: UPBO vs donor UPEJ

| Lesson | Detail |
|--------|--------|
| **Donor super is not “stock UPBO”** | `super-flip2.img` and rollback use `~/flip2-backups/donor-image-2026-10-28/super.img` (UPEJ/UPEN fingerprint). Lab merge baseline must eventually be **`$STOCK/super.img`** from **RWORP** (or other UPBO readback). |
| **Wrong super + vbmeta → loop** | Orange `vbmeta_system` not tied to the active super digest caused boot failure surface; recovery = donor vbmeta trio + donor super in **fastbootd** only. |
| **Serial in script** | Flash/rollback scripts should log and optionally refuse wrong `fastboot getvar serialno`. |

---

## Fastboot modes (4058G ONTK)

| Signal | Mode |
|--------|------|
| `product: gflip6` | Bootloader fastboot — **super full flash often stalls ~44%** |
| `product: Gflip6_NA_OM`, `is-userspace: yes` | **fastbootd** — required for reliable **super** write |

**What does not work (host-logged):**

- `fastboot reboot fastboot` from bootloader `gflip6` → hang at `< waiting for any device >`
- Autobooter alone → always `gflip6`, not fastbootd
- `adb reboot fastboot` when Android is stable → often returns to Android

**ONTK fastbootd recipe (validated):**

1. Bootloader: flash **`vbmeta_system.flip2-orange.img`** (kit).
2. `fastboot reboot fastboot` (host hang OK).
3. Phone bootloops; **Vol up + Power** at logo → fastbootd.
4. Run **`rollback-super-donor-fastbootd.sh`** or **`flash-ONTK-super-flip2.sh`** only after `probe-fastboot-mode.sh` shows userspace.

**Do not repeat:** concurrent `enter-fastbootd-and-flash-ONTK.sh`, autobooter loops, or repeated `fastboot reboot fastboot` while debugging keys.

Docs: ops hub `FASTBOOTD-FORENSICS-ONTK.md`, `HOW-TO-FASTBOOTD-ONTK.md`.

---

## AVB / verity (lab)

- Merge with **`--skip-avb`** for modified system partitions; flash **vbmeta trio** with `--disable-verity --disable-verification` in **bootloader** (`fastboot-vbmeta-disable.sh`).
- Orange vbmeta alone is **not** a substitute for full disable when digest mismatches.
- fastbootd may **reject** vbmeta writes — do vbmeta in bootloader when needed.

See `LAB-FLASH-ONTK-AVB-OFF.md` in ops hub and [IMAGE-BUILD.md](IMAGE-BUILD.md).

---

## Host automation vs user adb

When the user reaches Android and taps **Allow USB debugging**, background scripts that **`adb reboot bootloader`**, push zips and reboot, or run **`ontk-neutron-magisk-root.sh`** / **`ontk-recovery-borrowed-android.sh`** caused **immediate reboot** before authorization stuck.

**Rule:** Before manual Magisk or backup on device, **`pkill -f`** known watchers; one explicit script run; no duplicate `tee` pipeline starts.

---

## Install path: Tier B vs manual APK

- **Magisk full installer** on **donor super** may **FAIL** `pm install` for Launcher4, NullKeyboard, etc. — recover with **`pm install -r`** from `flip2-system-tree/system/app/` and **`first-boot.sh`** (HOME, shortcuts, `display_size_forced`).
- **Tier C** `flip2 setup full` is the idempotent live pipeline; prefer it over re-hand-installing from chat.
- Forkgram / Material Files may need on-device retry scripts under `/data/local/flip2/` when host wget TLS fails.

---

## Preloader and fastboot entry

- `adb reboot bootloader` on this hardware often **does not stay** in fastboot; use preloader vector / `~/flip2-enter-fastboot.sh` (see [IMAGE-BUILD.md](IMAGE-BUILD.md), donor [PRELOADER-PROBE-2026-10-27.md](PRELOADER-PROBE-2026-10-27.md)).
- **Never** flash EMMC_BOOT preloader header without explicit acceptance of brick risk.

---

## Wizard and manager

- Install path: host **adb push** + `su 0` (Companion), not WebUSB sync on Linux ([WIZARD-FAILURES.md](WIZARD-FAILURES.md)).
- **`wizardHostRunInstall`** must use **`adbRunShell`** so non-zero exit still surfaces stdout **`FAIL:`** lines in the UI.
- **`PROFILE_IDS`** in Companion must include every component id profiles can emit (e.g. appshelf, fdroid_basic, newpipe, vlc) or Apply rejects **`profile.list`**.
- Catalog **`size` + `sha256`** required for download gate (Sherpa tarballs included); regen **`pins.json`** after catalog edits.
- Destructive slices: **`erase`** (rooting / neutron boot), **`factory`** (boot restore from saved copy) — separate gates.
- **Check phone** (`verify.sh`) is the validity test for Tier B/C; trust **`SUMMARY: N passed, M failed`**, not a green status line alone.

---

## Speech (Sherpa-ONNX, Null Keyboard)

| Lesson | Detail |
|--------|--------|
| **Engine** | **Sherpa-ONNX only** on current IME; Whisper/Vosk removed from catalog and install path. See [SHERPA-STT.md](SHERPA-STT.md). |
| **EN vs UK** | English = streaming zipformer; Ukrainian = **offline** NeMo pack (no streaming UK upstream). |
| **Mic on Android 11** | IME uid stays background → **`SttForegroundService`** (microphone FGS) before **`AudioRecord`**. |
| **Hold `*`** | Mute **`FX_KEYCLICK`** (`sound_effects_enabled`), not just DTMF, or repeat clicks machine-gun the mic. |
| **Provision** | Wizard **`sherpa-en`** / **`sherpa-uk`** → `install.sh` extracts to `files/sherpa/{en,uk}`; verify checks **`tokens.txt`**. |
| **Forkgram** | Package **`org.forkgram.classic`** only; chat BACK delete hooks **`n20.onBackPressed`**, not LaunchActivity alone. |

---

## Promoting ops scripts into the repo

When a script under `~/flip2-backups/...` stabilizes:

1. Copy into `pipeline/<domain>/` with `source lib/bootstrap.sh`, serial/mode gates, and `exec >> tee log`.
2. Wire `bin/flip2` subcommand or document one canonical path in [PIPELINE.md](PIPELINE.md).
3. Link from this file and [AGENTS.md](../AGENTS.md).
4. Retire duplicate one-off copies in the ops hub or mark them **deprecated → pipeline/foo.sh**.

---

## Quick reference paths

| Purpose | Path |
|---------|------|
| Daily kit | `~/.local/share/flip2/pipeline/deploy/dist/flip2-image-kit-daily/` |
| Donor super rollback | `~/flip2-backups/donor-image-2026-10-28/super.img` |
| ONTK ops + logs | `~/flip2-backups/stock-UPBO-2026-11-02/` |
| Pre-wipe (MRV8 only) | `~/flip2-pre-wipe-backup/` |
| Stock readback plan | [STOCK-PHONE-DUMP.md](STOCK-PHONE-DUMP.md) |

---

*Last consolidated: 2026-11-04. Update this file when a gated drill or production incident changes behavior.*
