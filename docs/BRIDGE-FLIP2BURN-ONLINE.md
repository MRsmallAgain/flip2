# bridge.flip2burn.online — public Matrix + bridges

Matrix homeserver for Flip2 FluffyChat: **WhatsApp**, **Signal**, **Google Voice** via mautrix. Separate from static **flip2burn.online** (S3/CloudFront wizard only).

## URLs

| Endpoint | Purpose |
|----------|---------|
| `https://bridge.flip2burn.online` | Client API (FluffyChat homeserver URL) |
| `https://bridge.flip2burn.online/_matrix/client/versions` | Health / version probe |

Federation **8448** is disabled in v1 public posture.

## Architecture (v1)

```
Internet → Route 53 (bridge.flip2burn.online)
         → ALB (TLS 1.2+, ACM cert)
         → EC2:8080 (Caddy → Synapse; mautrix bridges on Docker network)
         → EBS encrypted (gp3)
```

Matrix cannot run on the wizard S3/CloudFront stack.

### Compute (defaults)

| Parameter | Default | Notes |
|-----------|---------|--------|
| `CapacityType` | **spot** | Single-instance ASG + persistent Spot; use `on-demand` for no interruptions |
| `InstanceType` | **t3.medium** | 2 vCPU / 4 GiB + 2 GiB swap in UserData |
| `VolumeSizeGb` | **80** | gp3 encrypted |

**Sizing**

| Type | RAM | Use |
|------|-----|-----|
| `t3.small` | 2 GiB | Lab / Synapse-only smoke test — not all three bridges hot |
| `t3.medium` | 4 GiB | **Recommended** start for Synapse + Postgres + 3 mautrix |
| `t3.large` | 8 GiB | Heavier sync or many rooms |

Not a multi-instance Spot **fleet** (that would need shared EBS/RDS and more ASG logic). This is **one** Spot-capable instance behind the ALB; on Spot reclaim, ASG replaces it — **re-bootstrap** from `/opt/flip2-bridge` on EBS if data lives on the root volume (`DeleteOnTermination: false` on root EBS).

### Scale path

| Stage | Change |
|-------|--------|
| v1 | One Spot/on-demand instance, Postgres in Docker volume |
| v2 | RDS Postgres, bridge hosts split |
| v3 | ECS + WAF rate rules on `/_matrix/*` |

## Security posture (public)

- **Registration disabled** in `synapse/homeserver.yaml.example`
- Users created with `register_new_matrix_user` or admin API only
- **Federation off** until explicitly enabled
- **Secrets** in SSM Parameter Store (`/flip2/bridge/*`), not git
- **SSH** blocked by default; use **SSM Session Manager**
- **SG:** EC2 accepts **8080** only from ALB SG; ALB accepts **443** from internet
- Pin mautrix image tags/digests in production

## Deploy

### 1. Stack (us-east-1)

```bash
cd ~/.local/share/flip2/infra/cloudformation

aws cloudformation deploy \
  --region us-east-1 \
  --stack-name flip2burn-bridge \
  --template-file flip2burn-bridge.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    BridgeHostname=bridge.flip2burn.online \
    ExistingHostedZoneId=ZXXXXXXXX \
    CapacityType=spot \
    InstanceType=t3.medium
```

Get **BridgeURL** from stack outputs.

### 2. Bootstrap EC2

```bash
flip2 bridges pack
# Copy dist/*.tar.gz to instance /opt/flip2-bridge

ssh or ssm start-session --target <InstanceId>
cd /opt/flip2-bridge && tar -xzf flip2-bridge-kit-*.tar.gz --strip-components=1
cp synapse/homeserver.yaml.example data/homeserver.yaml  # after synapse generate
# Fill .env from SSM; set SYNAPSE_SERVER_NAME=bridge.flip2burn.online

docker compose \
  -f compose.synapse.yml -f compose.vps.yml -f compose.prod.yml \
  --profile synapse --profile bridges up -d
```

### 3. Flip2 client

Homeserver: `https://bridge.flip2burn.online`

```bash
flip2 bridges on-device open-signin
```

## Artifacts

| Path | Role |
|------|------|
| `infra/cloudformation/flip2burn-bridge.yaml` | ALB + EC2 + DNS + ACM |
| `pipeline/bridge-kit/compose.prod.yml` | Caddy on :8080 behind ALB |
| `pipeline/bridge-kit/synapse/homeserver.yaml.example` | Hardened defaults |
| `pipeline/bridge-kit/bootstrap-ec2.sh` | Docker + layout |

## Related

- [BRIDGE-HOSTING.md](BRIDGE-HOSTING.md)
- [BRIDGES-FLIP2.md](BRIDGES-FLIP2.md)
