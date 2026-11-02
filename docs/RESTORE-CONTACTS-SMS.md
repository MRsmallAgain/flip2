# Restore contacts and SMS after factory reset

Flip 2 Companion is the supported restore. An unchecked SQLite file is still unsafe to drop onto a fresh ROM: schema and account binding differ, and `contacts.display_name` is not where names live. Companion checks the provider version, then writes counts only. It does not print names, numbers, or message bodies.

## Primary backup bundle

**`~/flip2-pre-wipe-backup/`** (donor `MRV8IJJVPRYTS4UG`, 2026-10-29)

| File | Use |
|------|-----|
| `readable/contacts2.db` | Pre-wipe contacts source for Companion |
| `readable/mmssms.db` | Pre-wipe messages source for Companion |
| `readable/contacts.vcf` | Manual Contacts import when Companion is not used |
| `readable/sms.csv` | Reference only |
| `readable/calls.csv` | Call log reference only |
| `readable/contacts-raw.txt` | Human-readable dump |

`metadata.img` is not a restore source. Other binary database copies from the old userdata are not a restore source either.

New saves from the Apps step live in `~/flip2-personal-backup`. That directory uses the same version-checked path. `factoryReadBackup` cannot read it. See [MANAGER.md](MANAGER.md).

Proven counts from the 2026-10-29 donor restore: contacts 18 named, 0 blank, 36 data rows; messages 84 SMS, 11 threads, 61 inbox, 23 sent. No attachments. The call log was not restored.

## Companion restore

Backup and restore need USB debugging and root. Do this before removing root. It does not wipe the phone, set device owner, or remove root.

In Flip 2 Companion, open **Apps**. The backup panel shows counts only (named, blank, data; sms, threads, inbox, sent; app count).

- **Contacts** — `check-contacts`, then a byte copy when `user_version` is 1401. Names live on `raw_contacts.display_name` and the mime name rows.
- **Messages** — `build-messages` rebuilds the database at `user_version` 670020. The builder inserts threads before SMS rows. PDU, part, and addr stay empty, so attachments stay out. Copying the raw `mmssms.db` onto `/data/data/com.android.providers.telephony/databases/` stays banned.
- **Pre-wipe** — Apps restores `readable/contacts2.db` and `readable/mmssms.db` from this bundle. A later save restores from `~/flip2-personal-backup` instead.

VCF import remains the manual alternative.

## Before you reset (if adb works again)

Prefer **Apps → Backup** in Companion while the phone is authorized and rooted. That writes `~/flip2-personal-backup`.

The staging copy below only captures files. It is not the restore:

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
adb shell su 0 sh -c 'mkdir -p /sdcard/Download/flip2-backup-staging/dbs'
adb shell su 0 sh -c 'cp /data/data/com.android.providers.contacts/databases/contacts2.db /sdcard/Download/flip2-backup-staging/dbs/'
adb shell su 0 sh -c 'cp /data/data/com.android.providers.telephony/databases/mmssms.db /sdcard/Download/flip2-backup-staging/dbs/'
adb pull /sdcard/Download/flip2-backup-staging ~/flip2-pre-wipe-backup-$(date +%F)/media/Download/flip2-backup-staging
```

## After reset — contacts (manual)

1. Complete setup **without** adding a Google account if you will set Headwind device owner.
2. Flip2 **Managed Apply** (see [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md)).
3. Copy VCF to phone:
   ```bash
   adb push ~/flip2-pre-wipe-backup/readable/contacts.vcf /sdcard/Download/
   ```
4. On phone: **Contacts** → menu → **Import** → pick `contacts.vcf` from Download.

## After reset — SMS

Android does not offer a standard import from `sms.csv`. The supported path is Companion **Apps → Restore messages**, saved or pre-wipe. `readable/sms.csv` stays on the PC as reference.

## After reset — call log

`calls.csv` is reference only. Importing `calllog.db` raw is unreliable. Companion does not restore the call log.

## Verify

Companion reports integer counts only. The 2026-10-29 restore was 18 named, 0 blank, 36 data rows, 84 SMS, 11 threads, 61 inbox, and 23 sent. Confirm with those counts. Leave names, numbers, and message bodies off the screen and out of notes.

## Related

- [MANAGER.md](MANAGER.md) — Apps backup, Managed profile, Headwind pin
- [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md) — post-reset MDM order
- [WIZARD-FAILURES.md](WIZARD-FAILURES.md) — Apply/verify escape hatches
