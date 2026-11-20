# bridge.flip2burn.online — Matrix stack (separate from wizard site)

**Stack:** `flip2burn-bridge` · **Template:** `flip2burn-bridge.yaml`

Hosts Synapse + mautrix bridges behind **ALB + ACM** at `https://bridge.flip2burn.online`.

The wizard stack (`flip2burn-site`) is static S3/CloudFront only — Matrix cannot run there.

## Prerequisites

- `aws login` (or configured AWS CLI) in **us-east-1**
- **HostedZoneId** for `flip2burn.online` (from `flip2burn-site` output `HostedZoneId`)
- IAM: EC2, ELB, ACM, Route53, IAM instance profile

## Deploy notes (2026-11-20)

- **ALB/TG names** must be ≤32 chars — template uses fixed names (`f2b-matrix-alb`, etc.), not `${StackName}`.
- **Spot + ASG** requires `SpotInstanceType: one-time` (not `persistent`).
- **Existing VPC** — pass `ExistingVpcId`, `PublicSubnetIdA/B` (account VPC limit).
- **AL2023 UserData** installs `docker` + Compose v2 binary (no `docker-compose-plugin` RPM).

If stack is `ROLLBACK_COMPLETE`, `delete-stack` and redeploy.

## Deploy

```bash
HZ=$(aws cloudformation describe-stacks --region us-east-1 \
  --stack-name flip2burn-site \
  --query "Stacks[0].Outputs[?OutputKey=='HostedZoneId'].OutputValue" --output text)

aws cloudformation deploy \
  --region us-east-1 \
  --stack-name flip2burn-bridge \
  --template-file flip2burn-bridge.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    BridgeHostname=bridge.flip2burn.online \
    ExistingHostedZoneId="$HZ" \
    CapacityType=spot \
    InstanceType=t3.medium
```

After ACM validates the bridge cert:

1. `flip2 bridges pack`
2. Copy tarball to EC2 `/opt/flip2-bridge`
3. `docs/BRIDGE-FLIP2BURN-ONLINE.md` + `bootstrap-ec2.sh`

## Parameters (cost)

| Parameter | Default | Notes |
|-----------|---------|--------|
| `CapacityType` | `spot` | `on-demand` if you cannot tolerate Spot reclaim |
| `InstanceType` | `t3.medium` | `t3.small` lab only; `t3.large` if bridges run hot |

## Outputs

- **BridgeURL** — FluffyChat homeserver
- **AutoScalingGroupName** — resolve instance ID via ASG for SSM Session Manager
