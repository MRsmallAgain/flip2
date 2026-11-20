# Tier 1 — On-device bridges on Flip2

**FluffyChat does not run bridges.** It only talks to a Matrix homeserver. Bridged networks (WhatsApp, Signal, Google Voice) need either:

1. **Beeper** — On-Device Connections + Beeper sync (official tier-1 path), or
2. **Network apps on the phone** for **pairing only** (QR / link) while the bridge runs on a server (tier 2).

Flip2 default: **FluffyChat** = inbox; **Forkgram** = Telegram.

## What runs on the Flip2

| Piece | On phone? | Notes |
|-------|-----------|-------|
| FluffyChat | Yes | Matrix login, rooms |
| mautrix daemons | No | Tier 2 VPS |
| Beeper + On-Device Connections | Yes, if APK installed | Not on F-Droid |
| WA/Signal for QR | Optional | Pairing UX is tight at 321×428 |

**v1 expectation:** WA / Signal / GV often need **tier 2** after tier 1 fails or Beeper won’t run on `armeabi-v7a`.

## Path A — Beeper On-Device

1. Install **Beeper** (Aurora, Play, or `adb install` APK from beeper.com).
2. Sign in to Beeper on the phone.
3. Add networks via **On-Device Connection** when offered.
4. FluffyChat: use same Matrix HS only if your spike confirms Beeper credentials work there.

## Path B — FluffyChat + VPS bridges (supported now)

1. `flip2 fluffychat release`
2. On phone: **Sign in** or **Login with Matrix-ID** (D-pad down from welcome).
3. Homeserver URL + user (phone-first).
4. Tier 2 bridges on VPS; rooms appear in FluffyChat.

```sh
flip2 bridges on-device status
flip2 bridges on-device open-signin
```

## Path C — QR pairing on flip (bridge on VPS)

Run mautrix on VPS; scan QR from FluffyChat/browser or use **enlarged QR on desktop** (Companion).

## Escalation

`docs/BRIDGE-HOSTING.md` tier 2 + `pipeline/bridge-kit/`

## Related

- [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md)
- [BRIDGES-FLIP2.md](BRIDGES-FLIP2.md)
- [BRIDGES-PHASE0-2026-11-20.md](BRIDGES-PHASE0-2026-11-20.md)
