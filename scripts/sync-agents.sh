#!/usr/bin/env bash
# sync-agents.sh — Compare installed agents against repo source and warn on divergence.
# Usage: bash scripts/sync-agents.sh [--fix]
#
# Default: report only (no changes).
# --fix:   copy repo agents → ~/.claude/agents/ (overwrites installed versions).
#
# Run after `git pull` to ensure installed agents match the repo.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLED_DIR="$HOME/.claude/agents"
REPO_AGENTS_DIR="$REPO_DIR/agents"
FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

if [ ! -d "$REPO_AGENTS_DIR" ]; then
  echo "ERROR: repo agents dir not found: $REPO_AGENTS_DIR" >&2
  exit 1
fi

if [ ! -d "$INSTALLED_DIR" ]; then
  echo "WARNING: ~/.claude/agents/ not found. Run setup-optimized.sh first." >&2
  exit 1
fi

DRIFT=0
MISSING=0
EXTRA=0

echo "Checking agent sync: $REPO_AGENTS_DIR → $INSTALLED_DIR"
echo ""

# Check repo agents against installed
while IFS= read -r repo_file; do
  name="$(basename "$repo_file")"
  installed_file="$INSTALLED_DIR/$name"

  if [ ! -f "$installed_file" ]; then
    echo "  MISSING  $name  (in repo, not installed)"
    ((MISSING++)) || true
    if $FIX; then
      cp "$repo_file" "$installed_file"
      echo "           → copied to $installed_file"
    fi
  else
    # Compare content (ignore model: lines since setup-optimized.sh patches those)
    repo_body=$(grep -v '^model: ' "$repo_file" || true)
    inst_body=$(grep -v '^model: ' "$installed_file" || true)
    if [ "$repo_body" != "$inst_body" ]; then
      echo "  DRIFT    $name  (repo and installed differ)"
      ((DRIFT++)) || true
      if $FIX; then
        # Preserve installed model: line, update everything else
        installed_model=$(grep '^model: ' "$installed_file" 2>/dev/null || echo "model: sonnet")
        cp "$repo_file" "$installed_file"
        sed -i "s/^model: .*/$installed_model/" "$installed_file"
        echo "           → updated (model tier preserved)"
      fi
    fi
  fi
done < <(find "$REPO_AGENTS_DIR" -name "*.md" | sort)

# Check for installed agents not in repo (locally added)
while IFS= read -r inst_file; do
  name="$(basename "$inst_file")"
  repo_file="$REPO_AGENTS_DIR/$name"
  if [ ! -f "$repo_file" ]; then
    echo "  LOCAL    $name  (installed, not in repo — consider committing)"
    ((EXTRA++)) || true
  fi
done < <(find "$INSTALLED_DIR" -name "*.md" | sort)

echo ""
if [ $DRIFT -eq 0 ] && [ $MISSING -eq 0 ] && [ $EXTRA -eq 0 ]; then
  echo "✓ All agents in sync."
else
  echo "Summary: $DRIFT drifted, $MISSING missing from install, $EXTRA local-only"
  if ! $FIX; then
    echo ""
    echo "To fix drift: bash scripts/sync-agents.sh --fix"
  fi
fi
