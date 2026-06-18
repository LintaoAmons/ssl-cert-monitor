#!/bin/bash
# Send message to Google Chat space via webhook (pure bash + curl)
#
# Usage: ./send-gchat.sh <subject> <text_body>
# Environment variables:
#   GCHAT_WEBHOOK_URL — Google Chat webhook URL

set -euo pipefail

SUBJECT="$1"
TEXT_BODY="$2"

if [ -z "${GCHAT_WEBHOOK_URL:-}" ]; then
  echo "[ERROR] GCHAT_WEBHOOK_URL not set"
  exit 1
fi

# Google Chat webhook accepts cards v2 for rich formatting
PAYLOAD=$(cat <<JSONEOF
{
  "cardsV2": [{
    "cardId": "ssl-monitor-$(date +%s)",
    "card": {
      "header": {
        "title": "${SUBJECT}",
        "subtitle": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
      },
      "sections": [{
        "widgets": [{
          "textParagraph": {
            "text": $(printf '%s' "$TEXT_BODY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '%s' "$TEXT_BODY" | jq -Rs '.' 2>/dev/null || echo "\"${TEXT_BODY//\"/\\\"\"}")
          }
        }]
      }]
    }
  }]
}
JSONEOF
)

HTTP_CODE=$(curl -s -o /tmp/gchat_response.txt -w "%{http_code}" \
  -X POST "$GCHAT_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

if [ "$HTTP_CODE" = "200" ]; then
  echo ">> Google Chat message sent successfully! (HTTP $HTTP_CODE)"
else
  echo ">> Google Chat send failed (HTTP $HTTP_CODE)"
  cat /tmp/gchat_response.txt
  exit 1
fi
