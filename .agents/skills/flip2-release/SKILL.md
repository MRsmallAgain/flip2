---
name: flip2-release
description: Pack and publish a Flip2 toolkit release on GitHub. Use whenever the user asks to cut a release, bump the Flip2 version, run the build-to-release cycle, rebuild the Magisk installers, or upload flip2-installer, flip2-packages, or the system tree.
---

# Flip2 release cycle

Repo: `~/.local/share/flip2`, GitHub `MRsmallAgain/flip2`, default branch `master`. Version lives in `pipeline/deploy/manifest.json` (`version`, currently `1.1.0-flip2`). Tag names are `v<version>` (`v1.1.0-flip2`). Dist output is gitignored.

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
cd ~/.local/share/flip2
```

## Pack

Do this only after the device tree you intend to ship is committed. Skills and docs do not change the zips; a payload change does.

```bash
flip2 installer pack --flavor full
flip2 installer pack --flavor clean
flip2 pack-all
flip2 image build-tree
```

`pack-all` writes `pipeline/deploy/dist/flip2-packages-<version>/` plus an inner `SHA256SUMS`. `image build-tree` writes `pipeline/deploy/dist/flip2-system-tree/`. Zip those two directories yourself (`flip2-packages-<version>.zip`, `flip2-system-tree-<version>.zip`). The installer zips are already `flip2-installer-full-magisk.zip` and `flip2-installer-clean-magisk.zip`.

Outer checksum file, same four names as the GitHub assets:

```bash
cd pipeline/deploy/dist
sha256sum flip2-installer-clean-magisk.zip flip2-installer-full-magisk.zip \
  flip2-packages-<version>.zip flip2-system-tree-<version>.zip > SHA256SUMS
sha256sum -c SHA256SUMS
(cd flip2-packages-<version> && sha256sum -c SHA256SUMS)
(cd flip2-system-tree && sha256sum -c SHA256SUMS)
```

Before uploading, confirm the keyboard inside the full installer:

- `lib/armeabi-v7a/libc++_shared.so` is in `payload/apks/nullkeyboard.apk` (Whisper will not load without it).
- `aapt dump badging` shows the version you meant to ship (`2.6.0` / versionCode 34 for 1.1.0-flip2).

## Publish

Push `master` first. Create the release from the commit you just pushed, not from an older local HEAD.

```bash
gh release create "v<version>" --target master --title "flip2 toolkit v<version>" --notes-file /tmp/flip2-notes.md \
  pipeline/deploy/dist/flip2-installer-clean-magisk.zip \
  pipeline/deploy/dist/flip2-installer-full-magisk.zip \
  pipeline/deploy/dist/flip2-packages-<version>.zip \
  pipeline/deploy/dist/flip2-system-tree-<version>.zip \
  pipeline/deploy/dist/SHA256SUMS
```

Match the v1.0.0 notes: a verify snippet (`sha256sum -c SHA256SUMS`), the four-tier table, and the "not included" list. Forkgram stays a separate GPL release (`flip2-13.0.2.0-r1`); the full installer downloads it. Vosk and Whisper models are not bundled. Say what was actually verified on the 4058G. Do not claim the cursor hold grabs the keypad unless a new on-device test showed the arrow swallowed.

`gh release create` on `master` becomes Latest. Do that only when this tag should replace `v1.0.0-flip2`.
