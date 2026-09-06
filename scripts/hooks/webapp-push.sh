#!/usr/bin/env bash
# webapp-push.sh — Session-end Stop hook: push cost row to Apps Script cache API.
# Called on session Stop. Exits 0 always — never blocks.

set -uo pipefail

ENV_FILE="$HOME/.ecc/team-workspace.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${ECC_WEBAPP_URL:=}"
: "${ECC_WEBAPP_TOKEN:=}"

if [ -z "$ECC_WEBAPP_URL" ] || [ -z "$ECC_WEBAPP_TOKEN" ]; then
  exit 0
fi

DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
USER_VAL="${USER:-unknown}"
PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo '')" 2>/dev/null || echo 'unknown')"
SESSION_ID="${CLAUDE_SESSION_ID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'unknown')}"

PAYLOAD="{\"action\":\"cost\",\"token\":\"$ECC_WEBAPP_TOKEN\",\"date\":\"$DATE\",\"user\":\"$USER_VAL\",\"project\":\"$PROJECT\",\"session_id\":\"$SESSION_ID\",\"model_tier\":\"sonnet\",\"tokens_in\":0,\"tokens_out\":0,\"cost_usd\":0,\"agent_name\":\"session\",\"task_summary\":\"session ended\"}"

curl -sf --max-time 8 -X POST "$ECC_WEBAPP_URL" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  >/dev/null 2>&1 || true

rm -f "/tmp/.ecc-webapp-pull-done"
exit 0
