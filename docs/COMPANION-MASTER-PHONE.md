# Master phone companion — Flip 2 as secondary device

The **smartphone** is the control plane; the **TCL Flip 2** is the wearable-style companion: inbox, alerts, D-pad apps, long battery. **Matrix admin** (`flip2admin`) is **break-glass only** — VPS recovery, bridge ops, manual user creation when automation is down. Normal onboarding never touches admin credentials on the phone or in daily apps.

## Roles

| Actor | Responsibility |
|-------|------------------|
| **Master phone app** (future) | Pair Flip, push settings, notification relay, hotspot bridge, QR/OAuth for Matrix & bridges |
| **Flip2 Companion (desktop)** | Flashing, wizard, ADB shell — same trust model as today |
| **Flip device** | FluffyChat, Forkgram, FlipMouse speeds, launcher — consumes signed config from master |

## Master phone app (v2+)

Android (or cross-platform) app paired to Flip over **USB debugging**, **Wi‑Fi ADB**, or **Flip hotspot** when user enables it.

### Settings & control (wizard parity)

- **FlipMouse / cursor:** Read/write profile speeds (homescreen vs SDL), same knobs as wizard `profiles.json` + device paths — no full desktop wizard required for tweaks.
- **Launcher / IME / profiles:** Push JSON bundles to `/data/local/flip2/` (SELinux ingest pattern from wizard staging).
- **Pairing:** One-time trust (ADB key or QR with Flip serial + confirm on master).

### Notifications

- **Capture on Flip:** Notification listener or privileged hook (root/Magisk) exports compact events (app, title, text, when).
- **Forward to master:** v1 over **Wi‑Fi / hotspot**: small on-device relay → master app WebSocket or opted-in sink; user picks apps.
- **Reverse:** Master pushes high-priority alert to Flip (vibrate / status) — smartwatch pattern.

### Network bridge via hotspot

When Flip shares **portable hotspot**, master phone can reach Flip for ADB/settings without USB. Optional Tailscale/VPN for homeserver access; document that hotspot is not an open bridge admin surface.

### Matrix / messaging onboarding (no admin)

End-user accounts via **registration shared secret** from trusted Companion/desktop only — see [COMPANION-ONBOARDING.md](COMPANION-ONBOARDING.md).

## Break-glass admin

| Use | Allowed |
|-----|---------|
| `MATRIX_ADMIN_*` in `.env` / SSM | VPS bootstrap, mautrix bridge ops |
| Wizard / master app daily flow | **Never** |
| FluffyChat on Flip | End-user `@user:bridge.flip2burn.online` only |

`apply-env-on-host.sh` creates admin only when `FLIP2_BRIDGE_BREAK_GLASS=1`.

## Phased delivery

| Phase | Deliverable |
|-------|-------------|
| 1 | Docs + cred scripts; wizard bridges panel |
| 2 | Desktop Companion: user registration (shared secret), WA QR panel |
| 3 | Master phone MVP: pair, cursor speed, notification forward |
| 4 | Hotspot ADB + notification relay without USB |

## Related

- [COMPANION-ONBOARDING.md](COMPANION-ONBOARDING.md)
- [BRIDGES-FLIP2.md](BRIDGES-FLIP2.md)
