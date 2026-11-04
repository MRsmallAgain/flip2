# Agent operating doctrine — Flip2

Mandatory mindset for **any** coding agent working on Flip2 (device ops, wizard, pipeline, image flash). Human-readable context: [LESSONS-LEARNED.md](LESSONS-LEARNED.md).

## Core principle

**All work teaches lessons. Complete work through pipeline scripts that pass gated recursion and validity testing — not through improvised shell in chat.**

## Before you act on a device

1. **Read** [LESSONS-LEARNED.md](LESSONS-LEARNED.md) when the task touches adb, fastboot, wipe, flash, backup, or Magisk.
2. **Identify serial and role** — donor (MRV8), daily driver (ONTK), stock readback (RWORP). Never apply donor-only rollback or lab super to the wrong serial without user explicit override.
3. **Check for an existing pipeline** — `flip2 <cmd>`, `pipeline/*/*.sh`, wizard slices with gates. **Extend the pipeline** instead of new one-offs in `~/flip2-backups/` unless the task is time-critical recovery; then **file a follow-up** to promote the script.
4. **Backup gate** — Before recommending factory reset, custom super, or rooting slice on a **daily driver**, confirm a **serial-matched** export exists (`MANIFEST.json`, pre-wipe bundle, or SP Flash readback plan). If missing, **run or document export first**; do not treat donor backups as substitute.

## Gated recursion (how to introduce change)

| Step | Action |
|------|--------|
| 1. Gate | Preconditions: health vars, hashes, typed words, mode probe (`gflip6` vs `Gflip6_NA_OM`). |
| 2. Recurse | Prove script on donor / expendable unit ([FACTORY-TEST.md](FACTORY-TEST.md) pattern). |
| 3. Validity | Post-step: `verify.sh`, `sha256sum`, size checks, log file with timestamps. |
| 4. Promote | Move to `pipeline/`, wire CLI, update [PIPELINE.md](PIPELINE.md) and [LESSONS-LEARNED.md](LESSONS-LEARNED.md). |

## Forbidden patterns (daily driver)

- Background **watchers** that `adb reboot bootloader` while user authorizes USB.
- **Two concurrent** flash/autoboot pipelines (duplicate `tee` logs = two writers).
- **`fastboot reboot fastboot`** loops on ONTK bootloader — use orange vbmeta recipe once, then keys.
- **Assuming** `fastboot fetch` or fastbootd vbmeta write works without reading ops forensics.
- **Flashing** lab `super-flip2` without user accepting donor-UPEJ baseline vs missing UPBO readback.
- **Skipping verify** after install because UI said OK ([WIZARD-FAILURES.md](WIZARD-FAILURES.md)).

## Allowed improvisation (must still be captured)

Emergency recovery when the phone is bootlooping **and** no pipeline stage exists yet:

- Run **one** documented ops script from `~/flip2-backups/stock-UPBO-2026-11-02/` with user-visible log path.
- After stability: **append** lesson to [LESSONS-LEARNED.md](LESSONS-LEARNED.md) or open a task to add `pipeline/recovery/` stage.

## Documentation duty

When you learn something new in a session:

1. Update [LESSONS-LEARNED.md](LESSONS-LEARNED.md) (table or bullet — keep it scannable).
2. If behavior is agent-specific, ensure [AGENTS.md](../AGENTS.md) links to the lesson doc.
3. Do **not** rely on chat history as the system of record.

## Skills

Load project skills before improvising:

| Skill | When |
|-------|------|
| `flip2-deploy` | Tiers, image flash, deroot |
| `flip2-adb` | USB permissions, unauthorized |
| Others | See [AGENTS.md](../AGENTS.md) |

## Cross-repo agents

If you are **not** in `~/.local/share/flip2` but the user asks about Flip2:

- Treat this file and [LESSONS-LEARNED.md](LESSONS-LEARNED.md) as authoritative for device safety.
- Prefer pointing the user to `flip2` CLI and pipeline over re-deriving fastboot recipes.
