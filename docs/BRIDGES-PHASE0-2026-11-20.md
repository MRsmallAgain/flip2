# Phase 0 spike — FluffyChat on Flip2 (ONTK)

**Device:** `ONTKKB9L7PEUX4Z5` — 4058G / Gflip6, `321x428` override, armeabi-v7a  
**Date:** 2026-11-20  
**Build:** F-Droid `chat.fluffy.fluffychat` **2.11.5** (3578), catalog pin verified, `flip2 fluffychat release`

## Install

- Installed via `flip2 fluffychat release` (streamed ~190 MB APK).
- Coexists with patched **Forkgram** (`org.forkgram.classic`).

## Launch / RAM

- Cold start reaches **MainActivity** welcome (“Secure [matrix] Communication”).
- **PSS ~108 MB** total after welcome screen (acceptable on lab unit; watch under bridge sync + multiple rooms).

## UI (welcome, no login yet)

| Observation | Flip2 impact |
|-------------|----------------|
| Large logo + headline | Usable at 321×428 |
| **Create new account** / **Sign in** / **Login with Matrix-ID** | After DPAD_DOWN scroll, all three CTAs are focusable |
| Kebab **Show menu** (top right) | Focusable; alternative to scrolling |
| D-pad **KEYCODE_DPAD_DOWN** (×5) | Focus moved to **Login with Matrix-ID** (uiautomator verified) |

**Existing account:** DPAD down to **Sign in** or **Login with Matrix-ID** → OK. No ⋮ menu required.

## Open (not tested on this pass)

- [x] D-pad: reach login CTAs without touch (DPAD_DOWN + OK)
- [ ] BACK in text fields (composer) after login
- [ ] Login to Beeper HS vs self-hosted Synapse
- [ ] One bridged room after VPS tier-2 bridges

## Next on phone (you)

1. **Existing Matrix account:** Open ⋮ menu → sign in → homeserver URL + user/password (phone-first).
2. **New user:** Either use Synapse on VPS (`pipeline/bridge-kit/`) or Beeper-provided HS per your tier-2 setup.
3. **Bridges:** Follow [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md) tier 2 for WhatsApp / Signal / Google Voice before expecting rooms in FluffyChat.

## CLI

```sh
flip2 fluffychat release --no-install   # re-verify pin
flip2 bridges doc
```
