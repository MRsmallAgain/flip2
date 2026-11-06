# Flip2 toolkit — agent notes

Repo: **`~/.local/share/flip2`** (`FLIP2_ROOT`).

## Operating doctrine (mandatory)

**Every session teaches lessons.** Prefer **pipeline-driven** work (`flip2` → `pipeline/<domain>/*.sh`) with **gates** (health checks, SHA-256 pins, typed words, serial/mode probes) and **validity tests** (`verify.sh`, manifests, `probe-fastboot-mode.sh`) — prove on donor hardware when possible, then promote the same script to the daily driver.

- **Read before device ops:** [docs/LESSONS-LEARNED.md](docs/LESSONS-LEARNED.md), [docs/AGENT-OPERATING-DOCTRINE.md](docs/AGENT-OPERATING-DOCTRINE.md)
- **Do not:** background adb reboot watchers, duplicate flash pipelines, or chat-only recipes without doc/pipeline follow-up
- **Backup gate:** no wipe/custom super on a daily driver without serial-matched export or explicit user waiver

Sub-agents under `.agents/` inherit this file plus [`.agents/AGENTS.md`](.agents/AGENTS.md).

## User goal

Set **menu grid slots 1–9** on TCL Flip2/Gflip6 via RRO overlay. Minimal web UI at `/edit`; prefer **`flip2 slot`** and **`slots.json`**.

## Commands (use these)

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 apply              # slots.json → device
flip2 slot <1-9> <pkg>    # one slot + apply
flip2 editor             # serve-editor.py + adb reverse
flip2 recovery           # after bad launcher Magisk module
```

## Pipelines

- **Overlay:** `pipeline/overlay/sync-slots.sh` → `launcher-overlay/scripts/sign-and-install.sh` → `after-root-enable.sh` (wired by `pipeline/overlay/apply.sh`).
- **Recovery:** `pipeline/recovery/resolve.sh` — never re-install `flip2_launcher3_icon_fix-magisk.zip`.

## Constraints

- RRO cannot add in-grid edit/long-press; only resources (`allapp_list`, strings).
- Apps with null launcher icons (e.g. Bouncy) crash **stock** Launcher3 — keep stock apps in slots until a non–whole-APK fix exists.
- Overlay needs **`targetName="Launcher3"`**, **`public.xml`** IDs aligned with stock Launcher3.
- Build: apktool, **`doNotCompress: arsc`**, zipalign, apksigner (debug key).

## Docs

- [README.md](README.md) — overview
- [docs/PIPELINE.md](docs/PIPELINE.md) — stages and layout
- [docs/SETUP-WIZARD.md](docs/SETUP-WIZARD.md) · [docs/MANAGER.md](docs/MANAGER.md) — Companion / TCL Flip2 Manager (Start · Apps · Set up)
- [docs/SHERPA-STT.md](docs/SHERPA-STT.md) — on-device dictation (authoritative; [WHISPER-STT.md](docs/WHISPER-STT.md) is historical)
- [docs/LESSONS-LEARNED.md](docs/LESSONS-LEARNED.md) — ops lessons (backup, fastbootd, Sherpa/wizard gates)
- [docs/AGENT-OPERATING-DOCTRINE.md](docs/AGENT-OPERATING-DOCTRINE.md) — gates, recursion, validity for agents
- `launcher-patch/RECOVERY.md`, `EMERGENCY-unresponsive.md`

## adb

If `no permissions`, user installs `launcher-patch/scripts/51-android-flip2-adb.rules`. ZCode sandbox may block USB; user runs `flip2` from local terminal.

## Project skills

Repeated workflows are in `.agents/skills/`. Read the matching `SKILL.md` before improvising a recipe.

| Skill | Use when |
|-------|----------|
| `flip2-adb` | `no permissions`, unauthorized, or USB missing from this shell |
| `flip2-ime-stt` | Null keyboard, Sherpa-ONNX (EN streaming / UK offline), `SttForegroundService`, `stt_lang`, hold-`*` dictation |
| `flip2-flipmouse` | Cursor toggle, 1s hold, shortcuts in mouse mode |
| `flip2-ondevice-keys` | `sendevent` holds on `/dev/input/event2` |
| `flip2-deploy` | Tiers A–D, `flip2 setup full`, de-root, image flash |
| `flip2-release` | Pack the four zips and publish a GitHub release |
