# SSL Certificate Monitor

Monitor SSL certificate (.cer) expiry and send email alerts via Azure Communication Services.

Pure bash — only requires `bash`, `curl`, and `openssl`. No Python or SDK needed.

## Usage

```bash
# Alert mode (default) — only certs expiring within 90 days
./check-certs.sh --mode alert /path/to/certs

# Full mode — all certs in a complete report
./check-certs.sh --mode full /path/to/certs

# Dry run — preview without sending email
DRY_RUN=true ./check-certs.sh --mode alert /path/to/certs
```

## Report Modes

### Alert Mode (`--mode alert`)
Only includes certificates expiring within `ALERT_DAYS` (default 90 days). Sends no email if all certs are healthy. Reports show SAN (Subject Alternative Name) for each certificate.

### Full Mode (`--mode full`)
Includes all certificates regardless of status. Always sends a report.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ACS_CONNECTION_STRING` | Yes* | — | Azure Communication Services connection string |
| `SENDER_ADDRESS` | Yes* | — | Sender email (e.g. `DoNotReply@xxx.azurecomm.net`) |
| `ALERT_EMAIL_TO` | Yes* | — | Recipient email address |
| `ALERT_DAYS` | No | `90` | Alert mode threshold (days) |
| `WARNING_DAYS` | No | `30` | Warning status threshold (days) |
| `CRITICAL_DAYS` | No | `14` | Critical status threshold (days) |
| `DRY_RUN` | No | `false` | Set `true` to skip email sending |

*Required when `DRY_RUN` is not `true`.

## GitHub Actions

The included workflow (`.github/workflows/cert-monitor.yml`) runs daily at 09:00 UTC and can be triggered manually with mode selection.

Add these as repository secrets (Settings → Secrets and variables → Actions):
- `ACS_CONNECTION_STRING` — Azure Communication Services connection string
- `SENDER_ADDRESS` — e.g. `DoNotReply@xxx.azurecomm.net`
- `ALERT_EMAIL_TO` — recipient email address

## Azure Communication Services Setup

1. Create a **Communication Services** resource in Azure Portal
2. Create an **Email Communication Services** resource
3. Provision a free Azure managed domain (Provision domains → Add a free Azure managed domain)
4. Connect the domain to the Communication Services resource (Email → Domains → Connect domain)
5. Copy the **Connection String** from Communication Services → Keys

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
