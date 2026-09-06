#!/usr/bin/env bash
# init-team-workspace.sh — Initialize local team workspace config for a new team member.
#
# Writes ~/.ecc/team-workspace.env with the Drive folder IDs and Sheet ID.
# Get these values from a teammate (Slack DM, 1Password shared vault, etc.).
#
# Usage: bash scripts/init-team-workspace.sh
#        bash scripts/init-team-workspace.sh --non-interactive  (uses env vars if already set)

set -euo pipefail
ENV_FILE="$HOME/.ecc/team-workspace.env"
NON_INTERACTIVE=false
[[ "${1:-}" == "--non-interactive" ]] && NON_INTERACTIVE=true

mkdir -p "$HOME/.ecc"

if [ -f "$ENV_FILE" ] && ! $NON_INTERACTIVE; then
  echo "Config already exists at $ENV_FILE"
  echo "Run with --non-interactive to overwrite from env vars, or edit the file directly."
  echo ""
  cat "$ENV_FILE"
  exit 0
fi

prompt_or_env() {
  local var_name="$1"
  local prompt_text="$2"
  local current="${!var_name:-}"
  if [ -n "$current" ]; then
    echo "$current"
  elif $NON_INTERACTIVE; then
    echo ""
  else
    read -rp "$prompt_text: " val
    echo "$val"
  fi
}

echo "ECC Team Workspace Setup"
echo "========================"
echo "Get these IDs from a teammate. They are the Google Drive folder/file IDs"
echo "from the shared ECC-Team-Workspace in Google Drive."
echo ""

ECC_GWS_ACCOUNT=$(prompt_or_env ECC_GWS_ACCOUNT      "Google account email (GWS account)")
ECC_DRIVE_ROOT=$(prompt_or_env ECC_DRIVE_ROOT         "Drive: ECC-Team-Workspace folder ID")
ECC_DRIVE_AGENTS=$(prompt_or_env ECC_DRIVE_AGENTS     "Drive: agents/ subfolder ID")
ECC_DRIVE_MEMORY=$(prompt_or_env ECC_DRIVE_MEMORY     "Drive: memory/ subfolder ID")
ECC_DRIVE_COST_LOGS=$(prompt_or_env ECC_DRIVE_COST_LOGS "Drive: cost-logs/ subfolder ID")
ECC_DRIVE_AUDIT=$(prompt_or_env ECC_DRIVE_AUDIT       "Drive: audit/ subfolder ID")
ECC_DRIVE_INSTINCTS=$(prompt_or_env ECC_DRIVE_INSTINCTS "Drive: instincts/ subfolder ID")
ECC_SHEETS_COST_ID=$(prompt_or_env ECC_SHEETS_COST_ID "Sheets: ECC Cost Tracking spreadsheet ID")

cat > "$ENV_FILE" << EOF
# ECC Team Workspace — local config (do not commit)
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
export ECC_GWS_ACCOUNT="$ECC_GWS_ACCOUNT"
export ECC_DRIVE_ROOT="$ECC_DRIVE_ROOT"
export ECC_DRIVE_AGENTS="$ECC_DRIVE_AGENTS"
export ECC_DRIVE_MEMORY="$ECC_DRIVE_MEMORY"
export ECC_DRIVE_COST_LOGS="$ECC_DRIVE_COST_LOGS"
export ECC_DRIVE_AUDIT="$ECC_DRIVE_AUDIT"
export ECC_DRIVE_INSTINCTS="$ECC_DRIVE_INSTINCTS"
export ECC_SHEETS_COST_ID="$ECC_SHEETS_COST_ID"
EOF

chmod 600 "$ENV_FILE"
echo ""
echo "Written to $ENV_FILE (mode 600)"
echo ""
echo "Source it in your shell profile to make it available to hooks:"
echo "  echo 'source ~/.ecc/team-workspace.env' >> ~/.bashrc"
echo ""
echo "Or call it at session start with: source ~/.ecc/team-workspace.env"
