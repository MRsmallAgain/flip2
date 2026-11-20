# Unified messaging on Flip2 — bridges + Matrix client

Flip2 Base ships **Forkgram** for native Telegram. This guide covers **bridged** chat: WhatsApp, Signal, and Google Voice (v1), using a **Matrix account** and **FluffyChat** on the phone.

## Mental model

| App | Networks |
|-----|----------|
| **Forkgram** (`org.forkgram.classic`) | Telegram only |
| **FluffyChat** (`chat.fluffy.fluffychat`) | WhatsApp, Signal, Google Voice (via Matrix bridges) |
| **Messages** (soft-key) | Carrier SMS (keep unless GV fully replaces SMS) |

Viber is backlog. Do not bridge-replace Telegram in v1.

## Hosting tiers

Pick one primary path; escalate when on-device fails.

| Tier | When | Doc |
|------|------|-----|
| **1 — On-device** | Try first where Beeper offers On-Device Connections | [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md#tier-1-on-device) |
| **2 — VPS** | WhatsApp / Signal / GV when tier 1 unavailable | [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md#tier-2-vps) |
| **3 — Homelab** | OPNsense/LAN + optional Tailscale | [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md#tier-3-homelab) |

Greenfield default: **Beeper account + VPS bridges (tier 2)** for v1 must-haves; tier 1 where supported.

## Install FluffyChat on the phone

```sh
# Phase 0 — stock F-Droid (armeabi-v7a)
flip2 fluffychat release --fdroid

# When catalog pin is live (patched mirror build)
flip2 fluffychat release
```

Provisioning: **phone-first** (login on Flip2) plus **Companion** copy helpers for homeserver URL and bridge pairing links.

## Pairing each network (v1)

### WhatsApp

- Usually **VPS or Beeper cloud/self-host** (`mautrix-whatsapp`).
- On Flip2: open pairing QR or link in browser; small screen — use Companion to show an enlarged QR on the PC if needed.
- Keep bridge process always-on; document battery if any on-device helper runs.

### Signal

- Typically **signald** or **mautrix-signal** on VPS.
- Signal linking UX on the flip: follow bridge docs; same QR enlargement tip.

### Google Voice

- **mautrix-gvoice** on VPS (US-centric).
- SMS threads appear as Matrix rooms in FluffyChat.

### Telegram

- Use **Forkgram**, not the Matrix bridge, for daily Telegram.

## Login Matrix on Flip2

1. Create or use a Matrix user (Beeper HS or your Synapse — see spike in `pipeline/bridge-kit/README.md`).
2. Open FluffyChat → set homeserver URL → sign in (phone-first).
3. After bridges sync, rooms appear; D-pad navigation may need **Flip2 Focus Bridge** until FluffyChat patches land.

## Troubleshooting

| Issue | Check |
|-------|--------|
| No bridged rooms | Bridge logs on VPS; bridge user invited to rooms |
| FluffyChat won’t login | HS URL, TLS, clock skew |
| BACK closes app in composer | Patches not applied yet — use on-screen delete or Focus Bridge |
| Notifications missing | API 30 background limits — whitelist battery for FluffyChat |

## Related

- [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md) — runbooks per tier
- [pipeline/fluffychat/README.md](../pipeline/fluffychat/README.md)
- [pipeline/forkgram/README.md](../pipeline/forkgram/README.md)
