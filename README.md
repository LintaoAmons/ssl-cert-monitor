# SSL Certificate Monitor

Monitor SSL certificate (.cer) expiry and send email alerts via Azure Communication Services.

Pure bash — only requires `bash`, `curl`, `openssl`, and `xxd`. No Python or SDK needed.

## Usage

```bash
# Alert mode (default) — only certs expiring within 90 days
./check-certs.sh --mode alert /path/to/certs

# Full mode — all certs in a complete report
./check-certs.sh --mode full /path/to/certs

# Dry run — preview without sending email
DRY_RUN=true ./check-certs.sh --mode alert /path/to/certs
```

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

## Report Modes

### Alert Mode (`--mode alert`)
Only includes certificates expiring within `ALERT_DAYS` (default 90 days). Sends no email if all certs are healthy.

### Full Mode (`--mode full`)
Includes all certificates regardless of status. Always sends a report.

## GitHub Actions

The workflow runs daily at 09:00 UTC and can be triggered manually with mode selection.

Add these as repository secrets:
- `ACS_CONNECTION_STRING`
- `SENDER_ADDRESS`
- `ALERT_EMAIL_TO`

## Testing with Mock Certs

```bash
# Generate 6 mock certificates with various expiry states
./generate-mock-certs.sh

# Test alert mode
DRY_RUN=true ./check-certs.sh --mode alert

# Test full mode
DRY_RUN=true ./check-certs.sh --mode full
```
