# Bridge hosting on Flip2 — tier runbooks

Three tiers for Matrix bridges (WhatsApp, Signal, Google Voice). No secrets in this repo — use env files on your host. Templates: `pipeline/bridge-kit/`.

## Overview

| Tier | Host | v1 networks | Cellular access |
|------|------|-------------|-----------------|
| **1 — On-device** | Flip2 / Beeper app | Try where Beeper exposes On-Device Connections | N/A |
| **2 — VPS** | Public cloud VM | WA, Signal, GV (mautrix-*) | Phone on any network if HS reachable |
| **3 — Homelab** | OPNsense / LAN box | Same as VPS | Often need **Tailscale** or port forward for mobile data |

Escalation: start tier 1 → on failure, provision tier 2 without changing Matrix user where possible.

## Tier 1 — On-device

**Goal:** Minimal infrastructure; phone stays signed in to Beeper where supported.

**Steps (conceptual):**

1. Create Beeper account (or Matrix user on Beeper HS).
2. On Flip2, install official Beeper **only if** you need on-device bridge helpers — unified inbox client remains **FluffyChat** per project default.
3. For each network, use Beeper’s in-app “On-Device Connection” when offered.
4. Document pass/fail per network on your device in spike notes (see BRIDGES-FLIP2.md).

**Limitations:** WhatsApp, Signal, and Google Voice often **require tier 2** in practice on a flip phone. Plan VPS before relying on tier 1 for v1 must-haves.

**Flip2 pairing:** QR scans on 321×428 — use Companion to display enlarged QR on desktop when the code is hard to read.

## Tier 2 — VPS

**Goal:** Always-on **mautrix** bridges + Matrix homeserver (or bridge-only to Beeper HS if your spike confirms that works).

**Prerequisites:**

- Linux VPS (2 GB+ RAM for Synapse + bridges, or bridge-only to external HS)
- Docker + Docker Compose
- Domain + TLS (Let’s Encrypt) for federation if self-hosting Synapse
- **Do not** commit `.env` or registration tokens

**Quick start:**

```sh
cd pipeline/bridge-kit
cp .env.example .env   # edit on server only
docker compose -f compose.vps.yml --profile bridges up -d
```

**Per-network (v1):**

| Bridge | Image / project | Pairing on Flip2 |
|--------|----------------|------------------|
| WhatsApp | `mautrix-whatsapp` | `login` QR in bridge logs / web UI |
| Signal | `mautrix-signal` | Signal link device flow |
| Google Voice | `mautrix-gvoice` | Google account OAuth per upstream docs |

**Backup:** Postgres volume + bridge sqlite volumes.

## Tier 3 — Homelab

Same as tier 2 on LAN; add **Tailscale** for cellular reachability without broad port exposure.

## Related

- [BRIDGES-FLIP2.md](BRIDGES-FLIP2.md)
- `pipeline/bridge-kit/README.md`
