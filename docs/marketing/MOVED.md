# The project moved off GitHub

**2026-11-13.** The GitHub account that hosted this project (`MRsmallAgain`) was
suspended. Every URL under `github.com/MRsmallAgain` now returns 404 — the
repository, its releases, and `raw.githubusercontent.com` alike. The cause is not
public; GitHub Support is the only party who can explain it, and an appeal is the
only route to a reinstatement.

**The toolkit itself is unaffected.** What changed is where the links point.

## Where things are now

| What | Where |
|------|-------|
| Setup wizard — start here | <https://flip2burn.online/> |
| Download files (installer zips, APKs, boot image, STT models) | `https://flip2burn.online/packages/<filename>` |
| Every filename, with size and SHA-256 | <https://flip2burn.online/catalog.json> |
| Source | <https://gitlab.com/mrsmallagain-group/flip2> (private for now) |
| Second source copy | private AWS CodeCommit repository `flip2` |

Two things worth knowing about the mirror:

- **It is not a stopgap.** It holds the same bytes, hash-verified by downloading
  them back, and it is what the wizard already fetched from — the browser path
  never used the GitHub URLs at all. Only the Companion's download button did.
- **There is no directory listing** on `packages/`; it returns 403 by design.
  `catalog.json` is the index: filename, byte size, SHA-256, licence, upstream.

CloudFront serves `accept-ranges`, so the 395 MB full installer resumes rather
than restarting.

## Safest first install

`flip2-installer-full-magisk.zip` — 395,628,118 bytes, SHA-256
`298b46685ed97fcad763bb2ae39ca48e58efb83b2102f1f60af0d6fce8a4317b`.

```bash
curl -fLO https://flip2burn.online/packages/flip2-installer-full-magisk.zip
sha256sum flip2-installer-full-magisk.zip
# 298b46685ed97fcad763bb2ae39ca48e58efb83b2102f1f60af0d6fce8a4317b
```

Flash it once in the Magisk app and reboot. Read `docs/SAFETY.md` first — full
features need root, and the wizard's *Put on phone* step is still experimental.

## What is still broken

- **GitHub release binaries** — gone with the account. The mirror replaces them.
- **The Forkgram fork** (`MRsmallAgain/TelegramAndroid`) — unreachable, so
  *republishing* the patched APK is blocked. The APK itself is mirrored and
  installs fine; `flip2 forkgram release` verifies it against the catalog pin.
- **`flip2 release`** — now publishes on GitLab, with the assets as links into
  the mirror rather than ~1.4 GB of uploads. Anything the mirror lacks is copied
  to the site bucket and polled until it serves the right byte count *before* the
  release exists. `--host github` is kept for a reinstatement.

## If you arrived from an old link

Everything the old release pages pointed at is on the mirror under the same
filenames. `catalog.json` is the authoritative list of what exists, with the size
and SHA-256 of each file — if a name is not in there, it was never published.

## The old announcements

The posts and threads in this directory (`v1.3.0-alpha.3/copy/`,
`v1.4.0-alpha.2/copy/`) still contain `github.com/MRsmallAgain` links. Their text
is **left exactly as published** — an announcement is a record of what was said,
so it is not being edited to look like it always pointed somewhere else. Each
file carries a note at the top saying the links are dead and where to go instead.

## Short notice you can paste

One line, for editing a post or replying in a thread:

> Moved: the GitHub account behind this was suspended, so those links 404 now.
> Start at https://flip2burn.online/ — same files, same SHA-256 pins.

Longer, for a new comment on an existing thread:

> Quick update on Flip2 toolkit: the GitHub account that hosted it was suspended
> on 2026-11-13, so every github.com/MRsmallAgain link in this thread is dead.
> The project is fine — installer zips, APKs and pins are served from
> https://flip2burn.online/packages/ (same bytes, verified against
> https://flip2burn.online/catalog.json), the wizard is at
> https://flip2burn.online/, and source is on GitLab:
> https://gitlab.com/mrsmallagain-group/flip2 (private for the moment). Safest
> first install is still the Tier B full installer, SHA-256 298b4668…a4317b.
