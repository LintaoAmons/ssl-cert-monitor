# SSL Certificate Monitor

Monitor SSL certificate (.cer) expiry and send alerts via email (Azure Communication Services) and/or Google Chat webhook.

Pure bash — only requires `bash`, `curl`, and `openssl`. No Python or SDK needed.

## Usage

```bash
# Alert mode (default) — only certs expiring within 90 days
./check-certs.sh --mode alert /path/to/certs

# Full mode — all certs in a complete report
./check-certs.sh --mode full /path/to/certs

# Dry run — preview without sending
DRY_RUN=true ./check-certs.sh --mode alert /path/to/certs
```

## Report Modes

### Alert Mode (`--mode alert`)
Only includes certificates expiring within `ALERT_DAYS` (default 90 days). Sends nothing if all certs are healthy.

### Full Mode (`--mode full`)
Includes all certificates regardless of status. Always sends a report.

## Notification Channels

Both channels can be used simultaneously. Set the relevant env vars to enable.

### Email (Azure Communication Services)

| Variable | Description |
|----------|-------------|
| `ACS_CONNECTION_STRING` | ACS connection string |
| `SENDER_ADDRESS` | Sender email (e.g. `DoNotReply@xxx.azurecomm.net`) |
| `ALERT_EMAIL_TO` | Recipient email address |

### Google Chat Webhook

| Variable | Description |
|----------|-------------|
| `GCHAT_WEBHOOK_URL` | Google Chat space webhook URL |

### Other

| Variable | Default | Description |
|----------|---------|-------------|
| `ALERT_DAYS` | `90` | Alert mode threshold (days) |
| `WARNING_DAYS` | `30` | Warning status threshold (days) |
| `CRITICAL_DAYS` | `14` | Critical status threshold (days) |
| `DRY_RUN` | `false` | Set `true` to skip sending |

## GitHub Actions

The included workflow runs daily at 09:00 UTC and can be triggered manually with mode selection.

Add these as repository secrets (Settings → Secrets and variables → Actions):
- `ACS_CONNECTION_STRING` — Azure Communication Services connection string
- `SENDER_ADDRESS` — e.g. `DoNotReply@xxx.azurecomm.net`
- `ALERT_EMAIL_TO` — recipient email address
- `GCHAT_WEBHOOK_URL` — Google Chat space webhook URL (optional)

## Azure Communication Services Setup

1. Create a **Communication Services** resource in Azure Portal
2. Create an **Email Communication Services** resource
3. Provision a free Azure managed domain (Provision domains → Add a free Azure managed domain)
4. Connect the domain to the Communication Services resource (Email → Domains → Connect domain)
5. Copy the **Connection String** from Communication Services → Keys

## Google Chat Webhook Setup

1. Open the Google Chat space → Apps & integrations → Webhooks
2. Create a webhook, copy the URL
3. Set as `GCHAT_WEBHOOK_URL`

## Mock Certificates

The repo includes 6 mock `.cer` certificates for testing:

| File | SAN | Status | Days Left |
|------|-----|--------|-----------|
| `app-expired.cer` | `DNS:app-expired.example.com` | EXPIRED | -5 |
| `api-critical.cer` | `DNS:api.example.com, DNS:*.api.example.com` | CRITICAL | 7 |
| `web-warning.cer` | `DNS:web.example.com, DNS:www.example.com, DNS:cdn.example.com` | WARNING | 25 |
| `staging-alert.cer` | `DNS:staging.example.com, DNS:staging-api.example.com` | OK (within 90d) | 60 |
| `backend-ok.cer` | `DNS:backend.example.com, DNS:backend-internal.example.com` | OK | 180 |
| `internal-ok.cer` | `DNS:internal.example.com, IP:10.0.0.1` | OK | 365 |

To regenerate mock certs:
```bash
./generate-mock-certs.sh
```

## Dependencies

- `bash`
- `curl`
- `openssl`

All standard in CI environments (Ubuntu runners, Alpine with `apk add bash curl openssl`).
