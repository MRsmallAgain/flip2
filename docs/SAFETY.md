# Flip 2 wizard — safety and brick risk

This page is for **people using the setup wizard**, not for developers. Read it before Apps → Apply, Prepare → Install, Prepare → Verify, or any footer link.

## What can actually brick a phone

On the TCL Flip 2, **permanent brick risk** usually means writing the wrong thing to **partitions the bootloader owns**: `super`, `vbmeta`, system, product, the **preloader**, or the **EMMC_BOOT** header. A bad **`boot`** image can **bootloop** the phone; you may recover with a **saved boot backup** (factory slice) or re-flash a known-good `boot` — that is not the same as “dead forever,” but it is serious.

The **manager** (Phone, Profile, Apps, and Prepare: credits, files, udev, connect, install, verify) **does not flash any partition**. Prepare → Install, and Apps → Apply profile, push files over ADB and run a root install script (Magisk modules, APKs, settings). That can leave the phone **misconfigured or half-installed**, but it is **designed to be retried** and does not erase flash partitions. Apply does not uninstall extras and does not wipe. Factory reset stays on the phone.

## Three different paths (pick on purpose)

| Path | Wipes user data? | Flashes partitions? | Best for |
|------|------------------|---------------------|----------|
| **Release installer zip** (Tier B full, Magisk) | No | No (modules in `/data/adb`) | First setup you want to **trust** |
| **Prepare install / Apply profile** | No | No | Same payload as the zip, **more automated**; Install is **experimental**. Managed adds the pinned Headwind launcher and needs Flip 2 Companion. |
| **Footer: “erase and root”** | **Yes** (bootloader unlock) | **`boot` only** (`neutron.img`) | A **spare phone** you can wipe |
| **Footer: “return to factory”** | Optional userdata wipe (on the phone) | **`boot` from your saved copy** | Restore **this phone’s** backed-up boot, not stock from the internet |

**Relocking the bootloader** after a modified boot is one of the most reliable ways to **hard-brick** this device. This project **never** offers “relock for safety.”

## Soft failures (annoying, usually fixable)

- Magisk module half-installed → remove module dir under `/data/adb/modules/`, reboot, or re-run install.
- Wrong HOME or IME → run install again or use `flip2` CLI docs.
- Verify **FAIL** lines → fix what the line names, then **Run verify** again.
- Display size → may need a **reboot** after install even when verify passes on the persisted setting.

## Recommended order for a daily driver

1. If the phone is **not** rooted: either accept a **full wipe** and use the **rooting slice** (type `erase`), **or** root by another method you trust — then continue.
2. Install flip2 with the **GitHub release full installer zip** (Magisk) **or** Apps → Apply or Prepare → Install after you understand the experimental banner. Base does not need Headwind. Managed does, and device owner is a separate step after you type `manage`.
3. Run **verify** (Apps → Run verify, or Prepare → Verify). **Reboot once.** Use the phone; keep a **boot backup** (factory slice) before experimenting with boot images.

## Hash verification

The wizard (and `catalog.json`) pin **SHA-256 and exact byte size** for every downloaded file. Do not push files that failed verification. The pinned full installer matches release **v1.2.0-flip2** (see `wizard/catalog.json`).

## Donor vs guinea pig

Project docs use a **donor** device ID for testing. **Do not** treat an unknown serial as “just try it” for rooting or factory slices.

## More detail

- [SETUP-WIZARD.md](SETUP-WIZARD.md) — how to run the page
- [MANAGER.md](MANAGER.md) — profiles, Headwind pin, and device owner versus Apply
- [RETURN-TO-FACTORY.md](RETURN-TO-FACTORY.md) — factory slice gates
- Recovery program **STOP C7** (agents): do not flash super/vbmeta on the documented donor bootloop case
