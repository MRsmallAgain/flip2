---
name: flip2-companion-pack
description: Pull the newest Flip2 sources (optional) and pack TCL Flip2 Manager (Electron companion) for Windows, Linux, or smoke-test. Use when the user asks to build the Windows installer, run pack:win, the companion pipeline, companion:win CI parity, or rebuild Manager after a release tag.
---

# Flip2 companion pack

Canonical stage: [`pipeline/ci/companion-pack.sh`](../../../pipeline/ci/companion-pack.sh). GitLab CI jobs `companion:smoke`, `companion:linux`, `companion:win` call the same script. Do not improvise `npm run pack:win` without syncing the tree the user cares about first.

Repo: `FLIP2_ROOT` — on this host `C:\Users\Tim\flip2` or `~/.local/share/flip2` on Linux. **Origin:** `https://gitlab.com/mrsmallagain-group/flip2.git` (HTTPS + credential helper). Version for installer filenames comes from [`companion/package.json`](../../../companion/package.json) `version` (aligned with release tags).

## Sync (before pack)

```bash
cd "$FLIP2_ROOT"   # or C:\Users\Tim\flip2
git fetch origin --tags
git pull origin master
git log -1 --oneline
```

On Windows, use `git -c credential.helper=manager fetch origin` if non-interactive fetch is required. SSH to `Timman6866/flip2` is not the canonical remote; use **mrsmallagain-group/flip2**.

Optional: checkout a release tag after pull — `git checkout v<version>-flip2` — only when the user wants that exact tag, not floating `master`.

## Pack (pipeline-driven)

From repo root:

```bash
bash pipeline/ci/companion-pack.sh smoke   # headless Companion pill-bar smoke
bash pipeline/ci/companion-pack.sh linux   # AppImage + linux-unpacked
bash pipeline/ci/companion-pack.sh win      # NSIS + portable .exe
```

The script: ensures `companion/node_modules` (`npm ci` in CI, else `npm install`), then runs the matching `npm` / electron-builder path (`prepack:win` → sync icons + platform-tools, then `pack:win`).

**Windows without bash:** equivalent is still the same npm entrypoints after sync:

```powershell
cd C:\Users\Tim\flip2\companion
npm run pack:win
```

Prefer `bash pipeline/ci/companion-pack.sh win` when Git Bash or WSL is available so local runs match CI.

## Verify (validity)

After `win`:

- `companion/dist/flip2-companion-<version>-win-x64.exe` exists (NSIS; electron-builder also emits portable target with the same basename pattern per `package.json` build config).
- `companion/dist/*.blockmap` for the NSIS build.
- `companion/dist/win-unpacked/TCL Flip2 Manager.exe` for quick local run without installing.

Read `<version>` from `companion/package.json`, not from an old filename in `dist/`.

```powershell
Get-ChildItem companion\dist -File -Filter "*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, Length, LastWriteTime
```

Signing is skipped unless CSC env is set (`no signing info identified` in builder log is normal for local builds).

## CI parity

See [`.gitlab-ci.yml`](../../../.gitlab-ci.yml): `companion:win` runs `companion-pack.sh win` on Linux+Wine (`allow_failure`); **authoritative Windows binaries** are built on a Windows host via this skill. Artifacts under `companion/dist/` are gitignored and are not published to the release mirror (see `flip2-release` for Magisk/installer assets).

## Docs

- [docs/SETUP-WIZARD-WINDOWS.md](../../../docs/SETUP-WIZARD-WINDOWS.md) — install/run Manager on Windows.
- [docs/PIPELINE.md](../../../docs/PIPELINE.md) — CI stages and companion pack commands.
- [docs/MANAGER.md](../../../docs/MANAGER.md) — Start · Apps · Device · Set up.

## Do not

- Point `origin` back at unreachable forks without the user asking.
- Treat GitHub `MRsmallAgain/flip2` as the sync source unless reinstatement and access are confirmed.
- Publish companion `.exe` to GitLab release links via `flip2 release` unless the project explicitly adds that asset class (mirror flow is installer/packages/system tree).
