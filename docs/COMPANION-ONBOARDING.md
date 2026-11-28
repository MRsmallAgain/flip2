# Flip 2 as smartphone companion — onboarding & QR

The Flip is a **secondary device**. The **master smartphone** (future app) or **desktop Flip2 Companion** owns QR scanning, OAuth, and registration. The Flip receives **short-lived bundles** over USB, LAN, or hotspot.

**Matrix admin is break-glass only** — never used in wizard, master app, or FluffyChat daily flow. See [COMPANION-MASTER-PHONE.md](COMPANION-MASTER-PHONE.md).

## Goals

| Layer | Master phone / Companion | Flip (companion) |
|-------|--------------------------|------------------|
| Matrix login | Register **end-user** with shared secret (server-side); show password once or token bundle | FluffyChat sign-in |
| WhatsApp | Scan bridge QR on **smartphone** WhatsApp | Matrix room only |
| Signal / GV | Link/OAuth on master device | Bot DM commands on Flip |
| Daily use | Settings, notifications, cursor speed | Inbox + D-pad apps |

## QR / deep-link options (by network)

### Matrix (FluffyChat)

1. **Manual (today):** Homeserver URL + user-chosen username/password on Flip (or registration via trusted Companion using **shared secret**, not admin API).
2. **Bundle v2:** `flip2://matrix-login` or `onboarding.json` with `hs`, `user`, short-lived token — pushed via ADB from master or desktop Companion.
3. **MSC3880 QR (future):** Optional; master phone scanner preferred over Flip camera.

**Today:** Wizard `bridges.js` — copy URL, open FluffyChat on device (`wizardHostShell`).

### WhatsApp (mautrix)

- Bridge posts QR in Matrix room after `login qr`.
- **Master phone / desktop:** Full-size QR display; user scans with smartphone WhatsApp.
- Flip only needs **user** Matrix session.

### Signal / GV

- Bot DM on Flip; sensitive steps on master phone or desktop.

## Signed onboarding bundle (proposed)

```json
{
  "v": 1,
  "hs": "https://bridge.flip2burn.online",
  "user": "alice",
  "login_token": "…",
  "expires": 1730000000,
  "bridges": ["whatsapp", "signal", "gvoice"]
}
```

Delivery: ADB push to staged path; no admin credentials in bundle.

## Phases

| Phase | Deliverable |
|-------|-------------|
| A | Wizard bridges panel |
| B | `rotate-creds`, SSM, break-glass admin on host |
| C | User registration via shared secret (Companion / master app) |
| D | WA QR projector (user Matrix session) |
| E | Master phone: notifications, settings, hotspot — [COMPANION-MASTER-PHONE.md](COMPANION-MASTER-PHONE.md) |

## Security

- `.env` gitignored; SSM on EC2.
- Admin password only for VPS break-glass (`FLIP2_BRIDGE_BREAK_GLASS=1`).

## Related

- [COMPANION-MASTER-PHONE.md](COMPANION-MASTER-PHONE.md)
- [BRIDGES-FLIP2.md](BRIDGES-FLIP2.md)
- [BRIDGE-FLIP2BURN-ONLINE.md](BRIDGE-FLIP2BURN-ONLINE.md)
