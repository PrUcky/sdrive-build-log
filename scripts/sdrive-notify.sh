#!/usr/bin/env bash
# ==============================================================================
# sdrive-notify.sh — Lightweight Webhook Alerting
# ==============================================================================
# Sends alerts to a configured webhook (e.g., Discord, Slack, Ntfy).
# Used by cron jobs and watchdogs to report failures instead of failing silently.
#
# Usage:
#   ./sdrive-notify.sh "ERROR" "Garage container is down!"
#   ./sdrive-notify.sh "SUCCESS" "Nightly blob backup completed (45GB)"
#
# Environment:
#   SDRIVE_WEBHOOK_URL must be set (typically in /etc/environment or crontab)
#
# Reference: weeks/week-07/day-43.md
# ==============================================================================
set -euo pipefail

LEVEL="${1:-INFO}"
MESSAGE="${2:-No message provided}"

# Fetch webhook from environment (do not hardcode secrets in scripts)
WEBHOOK_URL="${SDRIVE_WEBHOOK_URL:-}"

if [ -z "$WEBHOOK_URL" ]; then
    # Fallback to local logging if no webhook is configured
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [LOCAL-$LEVEL] $MESSAGE" >> /var/log/sdrive/alerts.log
    exit 0
fi

# Determine emoji based on level for visual parsing in the chat client
case "$LEVEL" in
    "ERROR"|"CRITICAL") EMOJI="🚨" ;;
    "WARN"|"WARNING")   EMOJI="⚠️" ;;
    "SUCCESS"|"OK")     EMOJI="✅" ;;
    "INFO"|*)           EMOJI="ℹ️" ;;
esac

# Format payload (Generic JSON structure, easily adaptable to Discord/Slack)
PAYLOAD=$(cat <<EOF
{
  "content": "$EMOJI **[sdrive $LEVEL]** $MESSAGE"
}
EOF
)

# Dispatch asynchronously with a 5-second timeout so it never hangs caller scripts
curl -s -m 5 -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null || {
    echo "Failed to send webhook alert."
    exit 1
}

echo "Alert dispatched: $LEVEL"
