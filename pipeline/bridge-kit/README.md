# Bridge kit — VPS / homelab templates (v1)

Docker Compose **fragments** for Matrix bridges (WhatsApp, Signal, Google Voice). **No secrets in git** — copy `.env.example` to `.env` on the server only.

## Phase 0 spike checklist

1. Choose homeserver: Beeper HS vs own Synapse (`compose.synapse.yml` optional).
2. Prove one inbound message per network into the Matrix user FluffyChat uses.
3. Record whether FluffyChat can log into Beeper HS with standard credentials.

## Files

| File | Purpose |
|------|---------|
| `compose.vps.yml` | Bridge services (profile `bridges`) |
| `compose.synapse.yml` | Optional minimal Synapse + Postgres (profile `synapse`) |
| `.env.example` | Placeholder variables — copy to `.env` on host |

## Usage (tier 2)

```sh
cp .env.example .env
# Edit: SYNAPSE_SERVER_NAME, secrets, bridge registration tokens
docker compose -f compose.vps.yml --profile bridges up -d
```

With local Synapse:

```sh
docker compose -f compose.synapse.yml -f compose.vps.yml --profile synapse --profile bridges up -d
```

Upstream docs:

- [mautrix-whatsapp](https://github.com/mautrix/whatsapp)
- [mautrix-signal](https://github.com/mautrix/signal)
- [mautrix-gvoice](https://github.com/mautrix/gvoice)

User-facing flow: `docs/BRIDGES-FLIP2.md`, `docs/BRIDGE-HOSTING.md`.
