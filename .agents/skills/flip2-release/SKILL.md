---
name: flip2-release
description: Pack and publish a Flip2 toolkit release on GitLab (links into the flip2burn.online package mirror). Use whenever the user asks to cut a release, bump the Flip2 version, run the build-to-release cycle, rebuild the Magisk installers, or publish flip2-installer, flip2-packages, or the system tree.
---

# Flip2 release cycle

Repo: `~/.local/share/flip2`, default branch `master`. GitLab
`mrsmallagain-group/flip2` is the public home (private as of 2026-11-13 — the
GitHub account was suspended); AWS CodeCommit `flip2` is the second copy. Version
lives in `pipeline/deploy/manifest.json` (read it — it moves every release). Tag
names are `v<version>`. Dist output is gitignored.

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
cd ~/.local/share/flip2
```

## Pack

Do this only after the device tree you intend to ship is committed. Skills and docs do not change the zips; a payload change does.

```bash
flip2 installer pack --flavor full
flip2 installer pack --flavor clean
flip2 installer pack --flavor image-post
flip2 pack-all
flip2 image build-tree
```

Optional before `image build-tree` for system FlipMouse: `flip2 flipmouse build-system` (see docs/FLIPMOUSE-SYSTEM.md).

`pack-all` writes `pipeline/deploy/dist/flip2-packages-<version>/` plus an inner `SHA256SUMS`. `image build-tree` writes `pipeline/deploy/dist/flip2-system-tree/`. Zip those two directories yourself (`flip2-packages-<version>.zip`, `flip2-system-tree-<version>.zip`). Installer zips: `flip2-installer-full-magisk.zip`, `flip2-installer-clean-magisk.zip`, `flip2-installer-image-post-magisk.zip`.

Do **not** hand-write the outer `SHA256SUMS`. `flip2 release` regenerates it from
the exact files it is about to publish (`ASSET_NAMES` in
`pipeline/deploy/release.sh`), which is what closed the drift bug that shipped
`v1.4.0-alpha.2-flip2` with sums from an older build. Verify the inner ones:

```bash
(cd pipeline/deploy/dist/flip2-packages-<version> && sha256sum -c SHA256SUMS)
(cd pipeline/deploy/dist/flip2-system-tree && sha256sum -c SHA256SUMS)
```

Before uploading, confirm the keyboard inside the full installer:

- The native libs resolve: `unzip -l payload/apks/nullkeyboard.apk | grep lib/`
  shows `libonnxruntime.so` and `libsherpa-onnx-jni.so` and no `libc++_shared.so`
  — that is **correct**. Both `.so` files link only `libc.so`/`libm.so`/`libdl.so`
  (`readelf -d | grep NEEDED`), i.e. libc++ is static. An older version of this
  file demanded `libc++_shared.so` and that gate was wrong; do not reintroduce it.
- `aapt dump badging` shows the version in
  `pipeline/ime/null-keyboard/AndroidManifest.xml` (`versionCode`/`versionName`).
  Read it from there rather than trusting a number written down here — that is
  how the hardcoded `1.1.0-flip2` in this file went stale.

## Publish

Push `master` first. Pack assets, write release notes, then:

```bash
flip2 release --notes /tmp/flip2-notes.md
```

Default backend is **GitLab**: `glab release create "v<version>" --ref master` with
the assets published as **links into the flip2burn.online package mirror**, not
uploads — the mirror already serves those bytes and `catalog.json` pins them, so
pushing ~1.4 GB into GitLab's package quota would duplicate hosted files. Any
asset the mirror is missing is copied to the site bucket, CloudFront-invalidated,
then polled until it serves the right byte count **before** the release is
created. After publishing, every link is read back and re-probed, so a release
page with a dead link fails the run instead of shipping silently.

`--host github` still uploads files to a GitHub release, for the day that account
is reinstated.

Then **`flip2 site deploy`** (regenerate push-manifest JS, `aws s3 sync wizard/`,
CloudFront `/*` invalidation) so https://flip2burn.online/ catalog/pins match the
tag. Use `flip2 release --skip-site` only when AWS is unavailable. Use
`flip2 release --dry-run` to print both steps without uploading — it also lists
which assets the mirror is missing and how many bytes that would copy. Manual
site-only refresh: `flip2 site deploy`.

`--republish` updates an existing release; with no `--notes` it reads the current
body back and re-sends it, because `glab release create` would otherwise replace
the description with nothing.

Match the v1.0.0 notes: a verify snippet (`sha256sum -c SHA256SUMS`), the four-tier table, and the "not included" list. Forkgram stays a separate GPL release (`flip2-13.0.2.0-r1`); the full installer downloads it. **Sherpa-ONNX** tarballs (EN + UK) are not bundled in the zip — fetch via wizard catalog or `flip2 ime sherpa` / `--sherpa-url` on pack. Say what was actually verified on the 4058G. Do not claim the cursor hold grabs the keypad unless a new on-device test showed the arrow swallowed.

A GitLab release has no "Latest" flag; it is discoverable by being the newest
tag. Creating one is still a public act — do it only when the user asked for a
release, never as a side effect of cutting a tag.
