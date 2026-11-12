# flip2burn.online — static wizard hosting

CloudFormation stack: **S3** (private) + **CloudFront** (OAC) + **ACM** (DNS validation) + **Route 53**.

**Region:** deploy the stack in **`us-east-1`** (ACM certs for CloudFront must be in us-east-1).

## Prerequisites

- AWS CLI configured
- Domain **flip2burn.online** registered (Route 53 or registrar)
- IAM permission for S3, CloudFront, ACM, Route 53

## Deploy (new hosted zone)

Use this if you will point the domain’s nameservers at the zone this stack creates.

```bash
cd ~/.local/share/flip2/infra/cloudformation

aws cloudformation deploy \
  --region us-east-1 \
  --stack-name flip2burn-site \
  --template-file flip2burn-site.yaml \
  --parameter-overrides \
    DomainName=flip2burn.online \
    CreateHostedZone=true \
    IncludeWww=true
```

Stack create often takes **15–30 minutes** (ACM validation + CloudFront). On first deploy with `CreateHostedZone=true`:

1. Copy **NameServers** from stack Outputs.
2. At your registrar, set **flip2burn.online** NS records to those four nameservers.

If the domain is **registered in Route 53** in the same account, you can instead create the hosted zone first and use `CreateHostedZone=false` + `ExistingHostedZoneId=Z...`.

## Upload site content

Sync the **wizard/** tree (not the whole flip2 repo):

```bash
BUCKET=$(aws cloudformation describe-stacks --region us-east-1 \
  --stack-name flip2burn-site --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
DIST=$(aws cloudformation describe-stacks --region us-east-1 \
  --stack-name flip2burn-site --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text)

aws s3 sync ~/.local/share/flip2/wizard/ "s3://${BUCKET}/" --delete \
  --cache-control "public,max-age=300" \
  --exclude ".git/*"

aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"
```

**Entry URL:** https://flip2burn.online/ (maps to `pages/index.html`).

## Parameters

| Parameter | Default | Notes |
|-----------|---------|--------|
| `DomainName` | `flip2burn.online` | Apex on cert + CloudFront alias |
| `IncludeWww` | `true` | `www` on cert and optional Route 53 aliases |
| `CreateHostedZone` | `true` | `false` + `ExistingHostedZoneId` if zone already exists |
| `ExistingHostedZoneId` | empty | Required when `CreateHostedZone=false` |
| `PriceClass` | `PriceClass_100` | NA/EU edges only |

## What this does **not** host

- **Companion** (Electron) — run locally; not part of this stack.
- **Large catalog binaries** — still downloaded from upstream URLs in `catalog.json`.
- **WebUSB** requires **HTTPS** (satisfied by CloudFront). Users still need **Chrome** (or Companion on desktop).

## Tear down

```bash
aws s3 rm "s3://${BUCKET}" --recursive   # empty bucket first
aws cloudformation delete-stack --region us-east-1 --stack-name flip2burn-site
```

## Validate template (optional)

```bash
aws cloudformation validate-template \
  --region us-east-1 \
  --template-body file://flip2burn-site.yaml
```
