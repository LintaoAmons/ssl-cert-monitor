#!/bin/bash
# Send email via Azure Communication Services Email REST API (pure bash + curl + openssl)
# No Python or SDK required — pipeline-friendly.
#
# Usage: ./send-email-acs.sh <to_email> <subject> <html_body>
# Environment variables:
#   ACS_CONNECTION_STRING — Azure Communication Services connection string
#   SENDER_ADDRESS        — sender email (e.g. DoNotReply@xxx.azurecomm.net)

set -euo pipefail

TO_EMAIL="$1"
SUBJECT="$2"
HTML_BODY="$3"

if [ -z "${ACS_CONNECTION_STRING:-}" ]; then
  echo "[ERROR] ACS_CONNECTION_STRING not set"
  exit 1
fi
if [ -z "${SENDER_ADDRESS:-}" ]; then
  echo "[ERROR] SENDER_ADDRESS not set"
  exit 1
fi

# --- Parse connection string ---
ENDPOINT=$(echo "$ACS_CONNECTION_STRING" | sed -n 's/.*endpoint=\([^;]*\).*/\1/Ip' | sed 's:/*$::')
ACCESS_KEY=$(echo "$ACS_CONNECTION_STRING" | sed -n 's/.*accesskey=\(.*\)/\1/Ip')
HOST=$(echo "$ENDPOINT" | sed 's|https://||;s|http://||')

# Convert access key from base64 to hex (handles binary keys with null bytes)
ACCESS_KEY_HEX=$(echo "$ACCESS_KEY" | openssl base64 -d -A | xxd -p | tr -d '\n')

hmac_sha256() {
  openssl dgst -sha256 -mac hmac -macopt "hexkey:${ACCESS_KEY_HEX}" -binary | openssl base64 -A
}

API_VERSION="2023-03-31"
PATH_AND_QUERY="/emails:send?api-version=${API_VERSION}"
URL="${ENDPOINT}${PATH_AND_QUERY}"

# --- Build JSON payload ---
json_escape() {
  if command -v python3 &>/dev/null; then
    python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()), end="")'
  elif command -v jq &>/dev/null; then
    jq -Rs '.'
  else
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
  fi
}

HTML_ESCAPED=$(echo "$HTML_BODY" | json_escape)
SUBJECT_ESCAPED=$(echo "$SUBJECT" | json_escape)

BODY=$(cat <<JSONEOF
{
  "senderAddress": "${SENDER_ADDRESS}",
  "content": {
    "subject": ${SUBJECT_ESCAPED},
    "html": ${HTML_ESCAPED}
  },
  "recipients": {
    "to": [{"address": "${TO_EMAIL}", "displayName": "${TO_EMAIL}"}]
  }
}
JSONEOF
)

# --- HMAC-SHA256 signing ---
DATE_STR=$(date -u "+%a, %d %b %Y %H:%M:%S GMT")
CONTENT_HASH=$(printf '%s' "$BODY" | openssl dgst -sha256 -binary | openssl base64 -A)

STRING_TO_SIGN="POST
${PATH_AND_QUERY}
${DATE_STR};${HOST};${CONTENT_HASH}"

SIGNATURE=$(printf '%s' "$STRING_TO_SIGN" | hmac_sha256)

# --- Send request ---
RESPONSE_FILE=$(mktemp)
HTTP_CODE=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
  -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-ms-date: ${DATE_STR}" \
  -H "x-ms-content-sha256: ${CONTENT_HASH}" \
  -H "Authorization: HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=${SIGNATURE}" \
  -H "x-ms-client-request-id: $(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "req-$$-$(date +%s)")" \
  -d "$BODY")

if [ "$HTTP_CODE" = "202" ]; then
  OPERATION_ID=$(cat "$RESPONSE_FILE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo ">> Email sent successfully! (HTTP $HTTP_CODE)"
  echo ">> Operation ID: $OPERATION_ID"

  POLL_URL="${ENDPOINT}/emails/operations/${OPERATION_ID}?api-version=${API_VERSION}"
  POLL_PATH="/emails/operations/${OPERATION_ID}?api-version=${API_VERSION}"

  for i in $(seq 1 6); do
    sleep 5
    POLL_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S GMT")
    POLL_HASH=$(printf '' | openssl dgst -sha256 -binary | openssl base64 -A)
    POLL_STR="GET
${POLL_PATH}
${POLL_DATE};${HOST};${POLL_HASH}"
    POLL_SIG=$(printf '%s' "$POLL_STR" | hmac_sha256)

    POLL_RESP=$(curl -s -X GET "$POLL_URL" \
      -H "x-ms-date: ${POLL_DATE}" \
      -H "x-ms-content-sha256: ${POLL_HASH}" \
      -H "Authorization: HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=${POLL_SIG}")

    STATUS=$(echo "$POLL_RESP" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo ">> Polling ($i/6): $STATUS"

    if [ "$STATUS" = "Succeeded" ]; then
      echo ">> Email delivered successfully!"
      rm -f "$RESPONSE_FILE"
      exit 0
    elif [ "$STATUS" = "Failed" ]; then
      echo ">> Email delivery failed:"
      cat "$RESPONSE_FILE"
      rm -f "$RESPONSE_FILE"
      exit 1
    fi
  done

  echo ">> Email accepted but delivery status unknown (timeout)."
  rm -f "$RESPONSE_FILE"
else
  echo ">> Email send failed (HTTP $HTTP_CODE)"
  cat "$RESPONSE_FILE"
  rm -f "$RESPONSE_FILE"
  exit 1
fi
