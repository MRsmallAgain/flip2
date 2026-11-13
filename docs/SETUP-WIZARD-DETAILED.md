# TCL Flip2 Manager — detailed setup walkthrough

Step-by-step guide for **Prepare** (Set up) on **Linux**, **Windows**, and **macOS**. Read [SAFETY.md](SAFETY.md) first. UI labels: [SETUP-WIZARD.md](SETUP-WIZARD.md). Behavior catalog: [MANAGER.md](MANAGER.md).

## Before you start

| Requirement | Why |
|-------------|-----|
| **Rooted TCL Flip 2** (Magisk) for full wizard install | `install.sh` runs as `su` and writes under `/data` |
| **USB debugging** enabled on the phone | Host adb or WebUSB needs an authorized device |
| **Conservative path?** | Use **Tier B** [`flip2-installer-full-magisk.zip`](https://flip2burn.online/packages/flip2-installer-full-magisk.zip) (verify its SHA-256 against `wizard/catalog.json`) — no PC wizard required |

**Recommended PC paths**

| OS | Best experience |
|----|-----------------|
| Linux | **Flip 2 Companion** (`flip2 companion`) — udev one-click, host adb install/verify |
| Windows | **Release `flip2-companion-*-win-x64.exe`** from GitHub (bundled adb) — see [SETUP-WIZARD-WINDOWS.md](SETUP-WIZARD-WINDOWS.md) |
| Any | Chrome + local HTTP server — WebUSB install (experimental vs Companion host adb) |

Firefox does not support WebUSB; use Chrome or Companion.

---

## Install the manager on your PC

### Option A — Flip 2 Companion (recommended)

**From source (Linux / Windows / macOS with Node.js):**

```bash
cd /path/to/flip2/companion   # from a clone of the repo (gitlab.com/mrsmallagain-group/flip2, currently private)
npm install
npm start
```

Or from a full toolkit tree:

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"   # Linux; adjust path on Windows
flip2 companion
```

**Windows (primary — release `.exe`):**

1. Build the installer with `npm run pack:win` (below). No prebuilt Windows `.exe` is published at the moment.
2. Run the installer or portable `.exe`. Launch **TCL Flip2 Manager** — **adb is bundled**; no separate Platform Tools install unless you override with `FLIP2_ADB`.
3. Install [Google USB Driver](https://developer.android.com/studio/run/oem-usb#Drivers) if Device Manager shows a warning on the phone.

**Build Windows package (developers, on Windows):**

```powershell
cd companion
npm install
npm run pack:win
# dist\flip2-companion-<version>-win-x64.exe (NSIS + portable)
```

The packaged app bundles `wizard/` under `resources/wizard`; you do not need a separate HTTP server.

### Option B — Browser only (Chrome)

```bash
cd wizard
python3 -m http.server 8000
```

Open **http://127.0.0.1:8000/pages/** in **Chrome** (not `file://`). On Linux, complete the **USB rules** step before WebUSB will behave; on Windows install OEM/Google USB drivers instead.

---

## Phone preparation (once per device)

1. Enable **Developer options** → **USB debugging**.
2. Connect USB. On the phone, accept **Allow USB debugging** (check “Always allow” if offered).
3. For Managed profile later: have local pins ready if needed — Headwind `~/Downloads/com.hmdm.launcher_15400.apk`, Where `~/Downloads/net.af0.where_1471.apk` (see [MANAGER.md](MANAGER.md)).

---

## Prepare — six steps (in order)

Open **Set up** or **Start setup** after choosing **Base** or **Managed** on **Start**.

### 1 · Ready

- Open **Credits** and review each maintainer's repository and license. This is required, not optional reading.
- Thank them for their work — this whole setup is built on it.
- Type **`yes`** exactly (lowercase) to unlock downloads. Typing it confirms that review.

Nothing fetches from the network until this gate passes.

### 2 · Get files

Every row in the table must show verified **size + SHA-256** matching `catalog.json` (includes **`sherpa-en`** and **`sherpa-uk`**).

| Action | When to use |
|--------|-------------|
| **Download** (per row) | Browser or Companion fetches from pinned URL |
| **Use file on this PC** | Companion scans Downloads / `flip2-wizard` and hashes candidates |
| Headwind / Where | No URL — place APK in Downloads at the pinned path; Companion matches hash |

**Continue** stays disabled until every required file verifies.

### 3 · USB rules

| Platform | What to do |
|----------|------------|
| **Linux** | Copy `wizard/51-android-flip2-adb.rules` to `/etc/udev/rules.d/`, reload udev, replug phone — or in Companion press **Install the rules for me** (polkit password). |
| **Windows** | Skip udev. Install [Google USB Driver](https://developer.android.com/studio/run/oem-usb#Drivers) or vendor driver; in Device Manager the phone should not show a yellow warning. `adb devices` → serial and `device`. |
| **macOS** | No udev; trust the device when prompted. adb from Platform Tools on `PATH`. |

Then press **Continue**.

### 4 · Connect

**Companion (host adb):**

1. Unplug other Android devices (wizard expects **one** authorized phone).
2. **Check host adb** in the strip or Connect step — message should say ready with serial.
3. If `unauthorized`: revoke USB debugging authorizations on phone, replug, accept prompt again.
4. If `no permissions` on Linux: redo USB rules step.

**Chrome WebUSB:**

1. Stop other adb servers: `adb kill-server` (Companion and browser cannot share the interface cleanly).
2. **Refresh** / claim device; pick TCL if chooser appears (Companion auto-picks `1bbb:0167` / `1bbb:0c01`).

### 5 · Put on phone

Experimental push of catalog bytes + `device/install.sh`, run as root on device.

**Companion highlights:**

- **`FAIL:`** lines from `install.sh` stop the run — read the line; fix file/profile, then retry.
- **Install stopped** with downgrades may need `pm install -r -d` on device (Companion paths handle many cases).
- After updating Companion code, **fully quit** the app so host adb changes load.

**Managed:** Companion must write `profile.list` — plain browser cannot Apply Managed profile list.

### 6 · Check phone

Runs `device/verify.sh` on the phone. UI shows **SUMMARY: N passed, M failed**.

- Target: **0 failed** when Sherpa tarballs and profile match catalog (often **27** or **28** checks depending on release).
- **Restart phone** when prompted after Magisk/module changes.

---

## Windows troubleshooting

| Symptom | Fix |
|---------|-----|
| `adb` is not recognized | Add Platform-Tools to PATH or set `FLIP2_ADB=C:\path\to\adb.exe` |
| `adb devices` empty | Driver missing; try Google USB Driver; another USB port/cable |
| `unauthorized` | Phone screen → allow debugging; replug |
| Companion opens but install fails immediately | Phone not rooted / `su` missing — flash neutron boot path first or use Tier B zip |
| Stuck on Get files | Sherpa ~290 MB — use Companion download; check disk space in `%USERPROFILE%\Downloads\flip2-wizard` |

---

## Linux troubleshooting

| Symptom | Fix |
|---------|-----|
| `no permissions` in `adb devices` | udev rules + replug; see `launcher-patch/scripts/51-android-flip2-adb.rules` |
| WebUSB claim failed | `adb kill-server`; close Companion if only using browser |
| pkexec dismissed | Rules not installed — manual `sudo cp` recipe on USB rules step |

More: [WIZARD-FAILURES.md](WIZARD-FAILURES.md).

---

## After Prepare

- **Apps** — single package install/remove, **Apply** profile, **Run check**, Managed **device owner** (`manage`), **Remove root** (`unroot`).
- **More: operate & recover** — erase-gated rooting (`erase`), return to factory (`factory`) — separate from Prepare; see [SETUP-WIZARD.md](SETUP-WIZARD.md).

---

## Quick reference links

- [SETUP-WIZARD.md](SETUP-WIZARD.md) — architecture, rooting/factory slices
- [SETUP-WIZARD-WINDOWS.md](SETUP-WIZARD-WINDOWS.md) — Windows-only checklist
- [MANAGER.md](MANAGER.md) — profiles, Headwind, device owner
- [SAFETY.md](SAFETY.md)
- [companion/README.md](../companion/README.md) — run and pack Companion
