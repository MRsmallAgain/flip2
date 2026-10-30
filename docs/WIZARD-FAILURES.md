# Flip 2 setup wizard — failure modes and escape hatches

Review based on donor `MRV8IJJVPRYTS4UG` runs (2026-10-29): WebUSB connect, host adb install, Companion on Linux.

The page is now **TCL Flip2 Manager**. The front door is Phone, Profile, Apps, and Prepare. The old numbered steps 4, 5, and 6 are still on the page, under Prepare: Connect, Install, and Verify. Apply on Apps opens that same Install subsection. Run verify on Apps opens Verify.

## Where the old steps are

| Old name | Now |
|----------|-----|
| Step 4 Connect | **Prepare → Connect** (USB debugging). Phone also has Refresh, USB rules, and USB debugging. Phone is status only. |
| Step 5 Install | **Prepare → Install**, or **Apps → Apply profile**. Apply writes `/data/local/flip2/profile.list`, then pushes and runs `install.sh`. |
| Step 6 Verify | **Prepare → Verify**, or **Apps → Run verify**. |
| (none) | **Profile** picks base, managed, or the disabled secure card. It does not push, uninstall, or wipe. |

Profile matters for install. A missing `profile.list` means full base, and Headwind is skipped. Managed Apply from a plain browser stops with `managed Apply requires Flip 2 Companion`. Host adb in Flip 2 Companion writes the list. WebUSB install does not.

## What broke (technical)

| # | Symptom | Cause | Fix in repo |
|---|---------|--------|-------------|
| 1 | Prepare → Connect: adb server holds USB | Host `adb` and WebUSB both want the debug interface | Companion: **Check host adb**; install uses host adb, not WebUSB |
| 2 | Prepare → Connect: **Continue to install** grey | Only enabled after WebUSB `ADB.connect()` | Companion auto-checks `adb devices`; **Check host adb** enables Continue |
| 3 | Prepare → Install: `timed out opening sync:` | WebUSB ADB `open('sync:')` 10s timeout on Linux | Companion: **host adb push** via `pipeline.js` `hostPushAndInstall` |
| 4 | Prepare → Install: `no phone is ready over adb` | Empty/unauthorized `adb devices` | User: USB debug + Allow; replug after wipe. Phone → Refresh shows whether host adb sees it. |
| 5 | Prepare → Install: `remote couldn't create file: Permission denied` | SELinux: shell `adbd` cannot write `/data/local/flip2/` | Push to `/sdcard/Download/flip2-wizard-staging`, `su cp` to incoming |
| 6 | Prepare → Install: `chmod … install.sh … Permission denied` | `adb push` + shell `chmod` on root-owned file | `install -m755` from staging as root (`su 0`); run script with `su 0 sh -c` |
| 7 | UI: red error but install **actually ran** | Companion failed after all pushes, before/during install.sh deploy; script may still be present from retry | **Continue to verify anyway** / run verify manually; see CLI below |
| 8 | Footer factory/root **hidden** | In a browser, `unlockAdvancedFooter()` runs after a verify **attempt**. A user stuck on Install never reaches Verify. | Companion shows the **Advanced** footer without verify. Install shows **Continue to verify anyway**. In a browser, run verify once under Prepare. |

## UI traps (no way out without knowing secrets)

1. **`inst-next` disabled** until the install promise resolves OK. Partial success (files pushed, chmod fail) leaves **Continue to verify** disabled on Prepare → Install. **Continue to verify anyway** is the way onward.
2. **Footer wipe/factory** stays hidden in a browser until verify has run once under Prepare. Flip 2 Companion shows that footer on open, and it also shows the on-phone wipe note.
3. **WebUSB vs host adb** messaging was contradictory (`adb kill-server` for Pick phone vs need adb for install). Companion install uses host adb. Pick phone is the browser path.
4. **Retry** only clears the install message. It does not run verify and it does not wipe.

## Escape hatches (always work)

### Wipe userdata (your goal)

The manager **never** wipes over USB. On the phone:

- **Settings → System → Reset options → Erase all data (factory reset)**, or
- Recovery: **Volume up + Power → Wipe data/factory reset**

Backup on PC: `~/flip2-pre-wipe-backup`.

Device owner is not part of Apply. On Apps, with Managed selected, type `manage` only when the phone has no accounts. If accounts exist, factory-reset on the phone first. This app does not edit `device_policies.xml`. If uninstall returns `DELETE_FAILED_DEVICE_POLICY_MANAGER`, stop. Break-glass is `docs/HEADWIND-MDM-RECOVERY.md`.

### Verify without the green install button

```bash
adb devices   # one device, "device"
adb shell su 0 sh -c 'sh /data/local/flip2/verify.sh'
```

Or in Companion: Prepare → Install → **Continue to verify anyway**, then **Run verify**. Apps → **Run verify** opens the same Verify subsection.

### Install without the page (host CLI)

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 setup full   # continues on per-step FAIL; uses adb throughout
```

`flip2 setup full` is the base install. It does not write a managed `profile.list` and it does not install Headwind.

### Factory / boot restore slice

- Companion: footer **return this phone to factory** is visible without a verify run.
- In a browser: Prepare → Install → **Continue to verify anyway**, then run verify once to unlock the footer.
- Factory slice still requires typing **`factory`** and the checkboxes. Wipe is on the phone only.
- Rooting still requires typing **`erase`**. It is not on the front-door pills.

## What the install step does now

- Prepare → Install shows **Continue to verify anyway** after an install failure.
- That same subsection notes that **factory reset is on the phone**, not in this app.
- Flip 2 Companion shows the **Advanced** footer links without requiring verify.
- If the install IPC fails but **verify.sh passes**, the UI treats that as success and enables **Continue to verify** (verify backfill).
- **Cleanup** failures (empty `incoming/`) do not fail the install.
- Companion install deploy: **`install -m755` fallback to `su cp` + chmod** when deploy throws.
- **`DONE: install complete`** in install.log wins over a late adb/chmod error when there is no `FAIL:` line.

## WebUSB vs host adb

| Place | Browser + Chrome | Flip 2 Companion |
|------|------------------|------------------|
| Prepare → Connect | WebUSB required for Pick phone | **Check host adb** is enough for Install and Verify |
| Prepare → Install / Apps → Apply | WebUSB sync (fragile on Linux). Managed Apply stops and asks for Companion. | Host **adb push** to `/sdcard/Download/flip2-wizard-staging`, then `su` copy, then `install.sh`. Writes `profile.list` first. |
| Prepare → Verify / Apps → Run verify | WebUSB | Host adb |

## Still unproven

- WebUSB ADB end-to-end install on Linux.
- Factory slice **wipe stage** on a real userdata erase (instructions only; the manager does not erase over USB).
- On-device Apply, remove, and `dpm set-device-owner` for the pinned Headwind launcher. Those need the donor plugged in and adb authorized.
