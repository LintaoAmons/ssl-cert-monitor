#!/bin/bash
# SSL Certificate Expiry Monitor
# Scans a directory for .cer (DER-encoded) files, checks expiry, sends alert email.
#
# Usage: ./check-certs.sh [options] [cert_directory]
#
# Options:
#   --mode alert    Only report certs expiring within ALERT_DAYS (default)
#   --mode full     Full scan report — all certs regardless of status
#
# Notification channels (set env vars to enable, can use both):
#   Email (ACS):
#     ACS_CONNECTION_STRING — Azure Communication Services connection string
#     ALERT_EMAIL_TO        — recipient email address
#     SENDER_ADDRESS        — sender email (e.g. DoNotReply@xxx.azurecomm.net)
#   Google Chat:
#     GCHAT_WEBHOOK_URL     — Google Chat space webhook URL
#
# Other env vars:
#   ALERT_DAYS            — threshold for alert mode (default: 90)
#   WARNING_DAYS          — days threshold for warning status (default: 30)
#   CRITICAL_DAYS         — days threshold for critical status (default: 14)
#   DRY_RUN               — set to "true" to skip actual sending

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse arguments ---
MODE="alert"
CERT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      CERT_DIR="$1"
      shift
      ;;
  esac
done

CERT_DIR="${CERT_DIR:-${SCRIPT_DIR}/certs}"
ALERT_DAYS="${ALERT_DAYS:-90}"
WARNING_DAYS="${WARNING_DAYS:-30}"
CRITICAL_DAYS="${CRITICAL_DAYS:-14}"
DRY_RUN="${DRY_RUN:-false}"
NOW_EPOCH=$(date +%s)

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================"
echo "  SSL Certificate Expiry Monitor"
echo "============================================"
echo "Mode           : $MODE"
if [ "$MODE" = "alert" ]; then
  echo "Alert threshold: ${ALERT_DAYS} days"
fi
echo "Warning        : ${WARNING_DAYS} days"
echo "Critical       : ${CRITICAL_DAYS} days"
echo "Dry run        : $DRY_RUN"
echo "--------------------------------------------"
echo ""

# --- Collect results ---
# Each entry: "status|days_left|filename|cn|end_date_str"
RESULTS=()
ALERT_ENTRIES=()
TOTAL_COUNT=0
ALERT_COUNT=0
HAS_CRITICAL=false

check_cert() {
  local cert_file="$1"
  local filename
  filename=$(basename "$cert_file")

  local cert_info
  cert_info=$(openssl x509 -inform DER -in "$cert_file" -noout -subject -enddate 2>/dev/null) || {
    echo -e "${RED}[ERROR]${NC} $filename — cannot parse certificate"
    return
  }

  # Extract SAN (preferred) with fallback to CN
  local san
  san=$(openssl x509 -inform DER -in "$cert_file" -noout -text 2>/dev/null \
    | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^ *//' | tr -d '\n')
  if [ -z "$san" ]; then
    # Fallback to CN if no SAN
    san=$(echo "$cert_info" | grep "subject" | sed 's/.*CN *= *//')
  fi

  local end_date_str
  end_date_str=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)

  local end_epoch
  end_epoch=$(date -jf "%b %d %T %Y %Z" "$end_date_str" +%s 2>/dev/null \
    || date -d "$end_date_str" +%s 2>/dev/null)

  local days_left=$(( (end_epoch - NOW_EPOCH) / 86400 ))

  local status color
  if [ "$days_left" -le 0 ]; then
    status="EXPIRED"
    color="$RED"
    HAS_CRITICAL=true
  elif [ "$days_left" -le "$CRITICAL_DAYS" ]; then
    status="CRITICAL"
    color="$RED"
    HAS_CRITICAL=true
  elif [ "$days_left" -le "$WARNING_DAYS" ]; then
    status="WARNING"
    color="$YELLOW"
  else
    status="OK"
    color="$GREEN"
  fi

  printf "  %-25s SAN=%-45s %b%-10s%b %3d days left  (expires %s)\n" \
    "$filename" "$san" "$color" "[$status]" "$NC" "$days_left" "$end_date_str"

  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  RESULTS+=("${status}|${days_left}|${filename}|${san}|${end_date_str}")

  if [ "$days_left" -le "$ALERT_DAYS" ]; then
    ALERT_ENTRIES+=("${status}|${days_left}|${filename}|${san}|${end_date_str}")
    ALERT_COUNT=$((ALERT_COUNT + 1))
  fi
}

# --- Scan ---
shopt -s nullglob
cert_files=("$CERT_DIR"/*.cer)

if [ ${#cert_files[@]} -eq 0 ]; then
  echo "No .cer files found in $CERT_DIR"
  exit 0
fi

echo "Found ${#cert_files[@]} certificate(s):"
echo ""

for f in "${cert_files[@]}"; do
  check_cert "$f"
done

echo ""
echo "--------------------------------------------"
echo "Total: $TOTAL_COUNT certs scanned, $ALERT_COUNT expiring within ${ALERT_DAYS} days"
echo "============================================"

# --- Build email ---
build_html_table() {
  local html=""

  while [ $# -gt 0 ]; do
    local entry="$1"; shift
    IFS='|' read -r e_status e_days e_file e_cn e_date <<< "$entry"
    local color_style
    case "$e_status" in
      EXPIRED|CRITICAL) color_style="color:red;font-weight:bold" ;;
      WARNING)          color_style="color:orange;font-weight:bold" ;;
      OK)               color_style="color:green" ;;
    esac
    html="${html}<tr><td style='${color_style}'>${e_status}</td><td>${e_file}</td><td>${e_cn}</td><td>${e_days}</td><td>${e_date}</td></tr>"
  done

  echo "$html"
}

build_gchat_text() {
  local text=""

  while [ $# -gt 0 ]; do
    local entry="$1"; shift
    IFS='|' read -r e_status e_days e_file e_cn e_date <<< "$entry"
    local icon
    case "$e_status" in
      EXPIRED)  icon="🔴" ;;
      CRITICAL) icon="🔴" ;;
      WARNING)  icon="🟡" ;;
      OK)       icon="🟢" ;;
    esac
    text="${text}${icon} *${e_status}* — \`${e_file}\` (${e_days}d)\n"
    text="${text}      SAN: ${e_cn}\n"
    text="${text}      Expires: ${e_date}\n"
  done

  echo -e "$text"
}

send_report() {
  local subject="$1"
  local table_rows="$2"
  local summary="$3"
  local send_entries=("${@:4}")

  local sent=false

  # --- Email (ACS) ---
  if [ "$DRY_RUN" = "true" ]; then
    echo ">> [DRY RUN] Would send:"
    echo "   Email to:  ${ALERT_EMAIL_TO:-<not set>}"
    echo "   GChat:     ${GCHAT_WEBHOOK_URL:+configured}${GCHAT_WEBHOOK_URL:-<not set>}"
    echo "   Subject:   $subject"
    return 0
  fi

  if [ -n "${ACS_CONNECTION_STRING:-}" ] && [ -n "${ALERT_EMAIL_TO:-}" ]; then
    local html_body="<h2>SSL Certificate Expiry Report</h2>
<p>Scan time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')</p>
<p>${summary}</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse;font-family:monospace'>
<tr style='background:#333;color:#fff'><th>Status</th><th>File</th><th>SAN</th><th>Days Left</th><th>Expires</th></tr>
${table_rows}
</table>
<p style='color:gray;font-size:0.9em'>Thresholds: Critical=${CRITICAL_DAYS}d, Warning=${WARNING_DAYS}d, Alert=${ALERT_DAYS}d</p>"

    bash "${SCRIPT_DIR}/send-email-acs.sh" "$ALERT_EMAIL_TO" "$subject" "$html_body"
    sent=true
  fi

  # --- Google Chat webhook ---
  if [ -n "${GCHAT_WEBHOOK_URL:-}" ]; then
    local gchat_text
    gchat_text=$(build_gchat_text "${send_entries[@]}")
    local gchat_body="${summary}\n\n${gchat_text}Thresholds: Critical=${CRITICAL_DAYS}d, Warning=${WARNING_DAYS}d, Alert=${ALERT_DAYS}d"

    bash "${SCRIPT_DIR}/send-gchat.sh" "$subject" "$(echo -e "$gchat_body")"
    sent=true
  fi

  if [ "$sent" = false ]; then
    echo ">> [SKIP] No notification channel configured. Set ACS_CONNECTION_STRING+ALERT_EMAIL_TO and/or GCHAT_WEBHOOK_URL."
    return 1
  fi
}

# --- Send based on mode ---
echo ""

if [ "$MODE" = "full" ]; then
  echo ">> Preparing full scan report..."
  TABLE=$(build_html_table "${RESULTS[@]}")
  SUBJECT="[SSL Monitor] Full Scan Report — ${TOTAL_COUNT} certificate(s)"
  SUMMARY="Full scan: ${TOTAL_COUNT} certificate(s), ${ALERT_COUNT} expiring within ${ALERT_DAYS} days."
  send_report "$SUBJECT" "$TABLE" "$SUMMARY" "${RESULTS[@]}"

elif [ "$MODE" = "alert" ]; then
  if [ "$ALERT_COUNT" -gt 0 ]; then
    echo ">> Preparing alert report (${ALERT_COUNT} cert(s) expiring within ${ALERT_DAYS} days)..."
    TABLE=$(build_html_table "${ALERT_ENTRIES[@]}")
    SUBJECT="[SSL Monitor] ${ALERT_COUNT} certificate(s) expiring within ${ALERT_DAYS} days"
    if [ "$HAS_CRITICAL" = true ]; then
      SUBJECT="[CRITICAL] ${SUBJECT}"
    fi
    SUMMARY="${ALERT_COUNT} of ${TOTAL_COUNT} certificate(s) expire within ${ALERT_DAYS} days."
    send_report "$SUBJECT" "$TABLE" "$SUMMARY" "${ALERT_ENTRIES[@]}"
  else
    echo ">> All certificates are healthy (none expiring within ${ALERT_DAYS} days). No alert sent."
  fi

else
  echo "[ERROR] Unknown mode: $MODE (use 'alert' or 'full')"
  exit 1
fi
