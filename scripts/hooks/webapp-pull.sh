#!/usr/bin/env bash
# webapp-pull.sh — Session-start hook: pull team memory + instincts from the Apps Script cache API.
# Called by PreToolUse (Bash matcher) on first tool use of the session.
# Exits 0 always — never blocks tool execution.
#
# Respects ECC_WEBAPP_PULL_DONE sentinel to fire only once per OS session.

set -uo pipefail

SENTINEL="/tmp/.ecc-webapp-pull-done-$$"
[ -f "/tmp/.ecc-webapp-pull-done" ] && exit 0

ENV_FILE="$HOME/.ecc/team-workspace.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${ECC_WEBAPP_URL:=}"
: "${ECC_WEBAPP_TOKEN:=}"

if [ -z "$ECC_WEBAPP_URL" ] || [ -z "$ECC_WEBAPP_TOKEN" ]; then
  exit 0
fi

PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo '')" 2>/dev/null || echo '')"

RESULT=$(curl -sf --max-time 5 \
  "$ECC_WEBAPP_URL?action=pull&token=$ECC_WEBAPP_TOKEN${PROJECT:+&project=$PROJECT}" \
  2>/dev/null || echo '{}')

MEMORY_COUNT=$(echo "$RESULT" | grep -o '"memory":\[' | wc -l || echo 0)
CACHED=$(echo "$RESULT" | grep -o '"cached":true' | wc -l || echo 0)
SOURCE=$(echo "$RESULT" | grep -o '"source":"[^"]*"' | cut -d'"' -f4 || echo '?')

touch "/tmp/.ecc-webapp-pull-done"

if [ "$CACHED" = "1" ]; then
  echo "[ECC] Team context loaded from cache (${SOURCE})." >&2
else
  echo "[ECC] Team context loaded from Sheets." >&2
fi

exit 0
