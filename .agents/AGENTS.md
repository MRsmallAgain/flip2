# Flip2 sub-agents (skills, tasks)

Parent repo rules: [../AGENTS.md](../AGENTS.md).

## Inherit

- [docs/AGENT-OPERATING-DOCTRINE.md](../docs/AGENT-OPERATING-DOCTRINE.md) — pipeline-first, gated recursion, validity testing
- [docs/LESSONS-LEARNED.md](../docs/LESSONS-LEARNED.md) — before adb/fastboot/flash/backup

## When running a skill

1. Load the skill's `SKILL.md` (do not re-derive from chat).
2. If the skill has no pipeline stage for the user's request, **extend** `pipeline/` or document the gap in LESSONS-LEARNED — do not leave a one-off as the only artifact.
3. Device work: one host writer; no parallel reboot scripts.

## Skills index

See table in [../AGENTS.md](../AGENTS.md#project-skills).
