# AWS CLI login for flip2burn deploy

**Canonical flow (same-device):** OAuth callback to `http://127.0.0.1:45876/oauth/callback`. No manual authorization code.

## Quick path

```bash
bash pipeline/deploy/aws-login-same-device-bg.sh
# Sign in in browser → brief redirect to 127.0.0.1 → done
aws sts get-caller-identity
bash pipeline/deploy/site-deploy-safe.sh
```

Foreground (leave terminal open until login completes):

```bash
bash pipeline/deploy/aws-login-same-device.sh
```

## Why not `aws login --remote`?

Cross-device (`aws login --remote`, `devtools/cross-device`, confirmation page) often returns **400** after account pick on Zorin/Linux desktops. Same-device avoids that step.

Do **not** open bare `https://us-east-1.signin.aws.amazon.com/oauth` — use the full `v1/authorize` URL from the script output only.

## Legacy / fallback

- `aws-login-copy-url.sh` + `aws-login-with-code.sh` — cross-device FIFO flow (when same-device cannot listen on localhost).
- Plain `aws login` — may trigger Chromium zygote errors; prefer same-device scripts with `BROWSER=/bin/true`.

## Config

`~/.aws/config` should include:

```ini
login_session = arn:aws:iam::006756247993:user/tim
region = us-east-1
```
