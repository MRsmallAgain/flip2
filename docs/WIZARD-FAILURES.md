# Flip 2 setup wizard — failure modes and escape hatches

Review based on donor `MRV8IJJVPRYTS4UG` runs (2026-10-29): WebUSB connect, host adb install, Companion on Linux.

## What broke (technical)

| # | Symptom | Cause | Fix in repo |
|---|---------|--------|-------------|
| 1 | Step 4: adb server holds USB | Host `adb` and WebUSB both want the debug interface | Companion: **Check host adb**; install uses host adb, not WebUSB |
| 2 | Step 4: **Continue to install** grey | Only enabled after WebUSB `ADB.connect()` | Companion auto-checks `adb devices`; **Check host adb** enables Continue |
| 3 | Step 5: `timed out opening sync:` | WebUSB ADB `open('sync:')` 10s timeout on Linux | Companion: **host adb push** via `pipeline.js` `hostPushAndInstall` |
| 4 | Step 5: `no phone is ready over adb` | Empty/unauthorized `adb devices` | User: USB debug + Allow; replug after wipe |
| 5 | Step 5: `remote couldn't create file: Permission denied` | SELinux: shell `adbd` cannot write `/data/local/flip2/` | Push to `/sdcard/Download/flip2-wizard-staging`, `su cp` to incoming |
| 6 | Step 5: `chmod … install.sh … Permission denied` | `adb push` + shell `chmod` on root-owned file | `install -m755` from staging as root (`su 0`); run script with `su 0 sh -c` |
| 7 | UI: red error but install **actually ran** | Companion failed after all 15 pushes, before/during install.sh deploy; script may still be present from retry | **Skip to verify** / run verify manually; see CLI below |
| 8 | Footer factory/root **hidden** | `unlockAdvancedFooter()` only after verify **attempt** — but user stuck on step 5 never reaches verify | Companion: **Advanced** footer without verify; **Skip to verify** on install |

## UI traps (no way out without knowing secrets)

1. **`inst-next` disabled** until install promise resolves OK — partial success (15/15 pushed, chmod fail) leaves user on step 5 forever.
2. **Footer wipe/factory** hidden until verify ran once — user who wants wipe after failed install cannot open factory slice from UI.
3. **WebUSB vs host adb** messaging was contradictory (`adb kill-server` for Pick phone vs need adb for install).
4. **Retry** only clears message; does not offer verify or wipe.

## Escape hatches (always work)

### Wipe userdata (your goal)

Wizard **never** wipes over USB. On the phone:

- **Settings → System → Reset options → Erase all data (factory reset)**, or
- Recovery: **Volume up + Power → Wipe data/factory reset**

Backup on PC: `~/flip2-pre-wipe-backup`.

### Verify without green install button

```bash
adb devices   # one device, "device"
adb shell su 0 sh -c 'sh /data/local/flip2/verify.sh'
```

Or in Companion after **Continue to verify anyway** (step 5) → **Run verify**.

### Install without wizard (host CLI)

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 setup full   # continues on per-step FAIL; uses adb throughout
```

### Factory / boot restore slice

- Companion: footer **return this phone to factory** (when visible), or step 5 **Continue to verify anyway** then run verify once to unlock footer in browser.
- Factory slice still requires typing **`factory`** and checkboxes; wipe is on-phone only.

## Recommended Companion UX (implemented in wizard)

- Step 5: **Continue to verify anyway** after install failure.
- Step 5: note that **factory reset is on the phone**, not in this wizard.
- Companion: show **Advanced** footer links without requiring verify.
- Step 5: if install IPC fails but **verify.sh passes**, UI auto-enables **Continue to verify** (verify backfill).
- Step 5: **cleanup** failures (empty `incoming/`) no longer fail the install step.
- Companion install deploy: **`install -m755` fallback to `su cp` + chmod** when deploy throws.
- Companion: **`DONE: install complete`** in install.log wins over a late adb/chmod error (no `FAIL:` lines).

## WebUSB vs host adb

| Step | Browser + Chrome | Flip 2 Companion |
|------|------------------|------------------|
| 4 Connect | WebUSB required | **Check host adb** enough for steps 5–6 |
| 5 Install | WebUSB sync (fragile on Linux) | Host **adb push** + staging |
| 6 Verify | WebUSB | Host adb |

## Still unproven

- WebUSB ADB end-to-end install on Linux.
- Factory slice **wipe stage** on real userdata erase (instructions only).
