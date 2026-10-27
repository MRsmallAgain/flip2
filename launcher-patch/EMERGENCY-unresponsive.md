# Phone not responsive — emergency recovery (launcher Magisk module)

The **Flip2 Launcher3 null icon fix** module can make the homescreen crash so fast that touch feels dead. The phone may still be **powered on and USB-connected**. Try these **in order**.

---

## 1. Hard reboot (do this first)

- Hold **Power** about **15–20 seconds** until the screen goes black and the phone vibrates or reboots.
- If nothing happens, try **Power + Volume Up** (hold 15–20 s) — common on MediaTek phones.
- Wait **30 seconds**, then short-press Power to boot normally.

---

## 2. Magisk safe mode (disables all modules for one boot)

1. **Power off** completely (step 1 if needed).
2. **Power on**; as soon as you see the **TCL / Android logo**, press and **hold Volume Down** until boot finishes (30–60 s).
3. You should get a **stable homescreen** (modules off for this boot only).
4. Open **Magisk** → **Modules** → **Remove** **Flip2 Launcher3 null icon fix** → **Reboot** normally.

Try holding **Volume Down** earlier if the first try fails (right when you feel vibration).

---

## 3. PC + USB (adb on your local PC)

Sandbox/remote shells often show adb **no permissions** — use **your** Linux machine where the phone worked before.

**Loop until module is gone:**

```bash
chmod +x ~/.local/share/flip2/launcher-patch/scripts/force-disable-module-loop.sh
~/.local/share/flip2/launcher-patch/scripts/force-disable-module-loop.sh
```

**Fix adb permissions:** `sudo adb kill-server && sudo adb devices` (accept RSA prompt if the screen flashes).

---

## 4. Recovery (volume keys + power)

Power off → **Power + Volume Up** at boot (see [flip2 wiki](https://github.com/neutronscott/flip2/wiki)). Stock recovery **cannot** delete Magisk modules unless **adb in recovery** works:

```bash
adb shell
# if you get a shell:
rm -rf /data/adb/modules/flip2_launcher3_null_icon_fix
reboot
```

**Wipe cache** rarely helps. **Factory reset** removes the module but **erases all data**.

---

## 5. Fastboot

Fastboot alone **does not** remove `/data/adb/modules`. Partition flashing is not on this branch; it lives on `feature/rooting-slice` and upstream, and only applies when you intend to restore firmware. Do not unlock an already-rooted Flip 2 — that erases the phone.

---

## After stable boot

- Do **not** re-flash `flip2_launcher3_icon_fix-magisk.zip`.
- Keep menu slot 5 on a stock app until a safer icon fix exists.
