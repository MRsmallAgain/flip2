# Restore contacts and SMS after factory reset

After wiping the phone, use the **readable exports** from a pre-wipe backup. Raw SQLite DBs are **not** safe to drop back onto a fresh ROM (schema/account binding differs).

## Primary backup bundle

**`~/flip2-pre-wipe-backup/`** (donor `MRV8IJJVPRYTS4UG`, 2026-10-29)

| File | Use |
|------|-----|
| `readable/contacts.vcf` | Import into Contacts (best path) |
| `readable/sms.csv` | Reference / manual re-entry; see below |
| `readable/calls.csv` | Call log reference |
| `readable/contacts-raw.txt` | Human-readable dump |

`metadata.img` and binary `*.db` copies are for **this phone’s old userdata**, not for restore after wipe.

## Before you reset (if adb works again)

If the phone unlocks or you get **authorized adb** briefly:

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
# Staging on device then pull (root)
adb shell su 0 sh -c 'mkdir -p /sdcard/Download/flip2-backup-staging/dbs'
adb shell su 0 sh -c 'cp /data/data/com.android.providers.contacts/databases/contacts2.db /sdcard/Download/flip2-backup-staging/dbs/'
adb shell su 0 sh -c 'cp /data/data/com.android.providers.telephony/databases/mmssms.db /sdcard/Download/flip2-backup-staging/dbs/'
adb pull /sdcard/Download/flip2-backup-staging ~/flip2-pre-wipe-backup-$(date +%F)/media/Download/flip2-backup-staging
```

Regenerate VCF/CSV from DBs if you have `sqlite3` on the host (same workflow used for the 2026-10-29 bundle).

## After reset — contacts

1. Complete setup **without** adding a Google account if you will set Headwind device owner.
2. Flip2 **Managed Apply** (see [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md)).
3. Copy VCF to phone:
   ```bash
   adb push ~/flip2-pre-wipe-backup/readable/contacts.vcf /sdcard/Download/
   ```
4. On phone: **Contacts** → menu → **Import** → pick `contacts.vcf` from Download.

## After reset — SMS

Android does not offer a standard “import SMS from CSV” on stock MMS.

Options:

- **SMS Backup & Restore** (or similar): export format from a working phone, restore on new setup — only if you had such a backup.
- **Manual**: use `readable/sms.csv` on the PC as reference while re-creating important threads.
- **Do not** copy `mmssms.db` over `/data/data/com.android.providers.telephony/databases/` on a fresh user unless you know the exact provider version match (usually fails or corrupts).

## After reset — call log

Same as SMS: `calls.csv` is reference only; importing `calllog.db` raw is unreliable.

## Verify

```bash
adb shell content query --uri content://contacts/contacts --projection display_name | head
```

## Related

- [MANAGER.md](MANAGER.md) — Managed profile, Headwind pin
- [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md) — post-reset MDM order
- [WIZARD-FAILURES.md](WIZARD-FAILURES.md) — Apply/verify escape hatches
