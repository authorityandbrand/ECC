#!/usr/bin/env bash
# setup-optimized.sh — Portable, idempotent ECC setup with token optimizations.
#
# Run this in any new environment to reproduce the full optimized Claude Code setup:
#   bash scripts/setup-optimized.sh
#
# What it does:
#   1. Installs ECC full profile into ~/.claude/
#   2. Removes unused language rule packs (keeps only common/ by default)
#   3. Writes the quiet-noisy-commands PreToolUse hook
#   4. Writes the truncate-bash-output PostToolUse safety-net hook
#   5. Wires both hooks into ~/.claude/settings.json
#   6. Downgrades simple/mechanical agents from sonnet → haiku
#   7. Downgrades complex-but-not-architectural agents from opus → sonnet
#
# To keep specific language rule packs, pass them as arguments:
#   bash scripts/setup-optimized.sh typescript python golang
#
# Requirements: Node.js >=18, git, Claude Code >=2.1

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"

# ── 1. Install ECC full profile ────────────────────────────────────────────────
echo "[1/6] Installing ECC full profile..."
cd "$REPO_DIR"
if [ ! -d node_modules ]; then
  npm install --no-audit --no-fund --loglevel=error
fi
node scripts/install-apply.js --target claude --profile full --enable-hooks

# ── 2. Prune unused language rule packs ───────────────────────────────────────
echo "[2/6] Pruning language rule packs..."
ALL_LANGS=(angular arkts cpp csharp dart fsharp golang java kotlin nuxt perl php python react react-native ruby rust swift typescript vue web)
KEEP_LANGS=("$@")   # any language names passed as CLI args

for lang in "${ALL_LANGS[@]}"; do
  keep=false
  for k in "${KEEP_LANGS[@]}"; do
    [[  "$k" == "$lang" ]] && keep=true && break
  done
  target="$CLAUDE_DIR/rules/ecc/$lang"
  if [ -d "$target" ] && [ "$keep" = false ]; then
    rm -rf "$target"
    echo "  removed: rules/ecc/$lang"
  elif [ "$keep" = true ]; then
    echo "  kept:    rules/ecc/$lang"
  fi
done

RULE_TOKENS=$(find "$CLAUDE_DIR/rules/" -name "*.md" -exec wc -c {} \; 2>/dev/null | awk '{s+=$1} END {print int(s/4)}')
echo "  rules footprint: ~${RULE_TOKENS} tokens"

# ── 3. Write quiet-noisy-commands PreToolUse hook ─────────────────────────────
echo "[3/6] Writing quiet-noisy-commands hook..."
mkdir -p "$HOOKS_DIR"
cat > "$HOOKS_DIR/quiet-noisy-commands.js" << 'HOOK'
#!/usr/bin/env node
// PreToolUse hook: rewrites known-noisy Bash commands before they run.
// Noisy commands (installs, builds, test runs) are wrapped so only errors,
// failures, and the final summary line come back. Short/unknown commands pass through.

const NOISY_PATTERNS = [
  /\bnpm\s+(install|ci|i)(\s|$)/,
  /\byarn(\s+(install|add))?\s*$/,
  /\byarn\s+(install|add)\b/,
  /\bpnpm\s+(install|add|i)\b/,
  /\bbun\s+(install|add)\b/,
  /\bpip3?\s+install\b/,
  /\bconda\s+install\b/,
  /\bbrew\s+install\b/,
  /\bapt(-get)?\s+install\b/,
  /\bcargo\s+install\b/,
  /\bgo\s+get\b/,
  /\bnpm\s+run\s+build\b/,
  /\byarn\s+build\b/,
  /\bpnpm\s+build\b/,
  /\bbun\s+run\s+build\b/,
  /\bcargo\s+build\b/,
  /\bgo\s+build\b/,
  /\bmvn\s+(package|install|compile)\b/,
  /\bgradle\b/,
  /\bmake\b/,
  /\bnext\s+build\b/,
  /\bvite\s+build\b/,
  /\btsc\b/,
  /\bnpm\s+(test|run\s+test)\b/,
  /\byarn\s+test\b/,
  /\bpnpm\s+test\b/,
  /\bjest(\s|$)/,
  /\bvitest(\s|$)/,
  /\bpytest(\s|$)/,
  /\bcargo\s+test\b/,
  /\bgo\s+test\b/,
  /\bmocha\b/,
  /\bnode\s+tests\/run-all/,
];

const KEEP_RE = /error|Error|ERROR|fail|Fail|FAIL|warn|Warn|WARN|ERR!|added|removed|updated|audited|packages|deprecated|vulnerabilit|PASS|pass|Tests:|Test Suites:|Suites:|passed|failed|skipped|pending|Done in|built in|compiled|npm warn|npm notice|\[\d+\/\d+\]|exit code|Exit code|SyntaxError|TypeError|ReferenceError|Cannot find|Module not found|ENOENT|EACCES|ETIMEDOUT/i;

function wrap(cmd) {
  const filter = KEEP_RE.source;
  return `( ${cmd} ) 2>&1 | grep -aE "${filter}" | tail -50 || true`;
}

let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  try {
    const obj = JSON.parse(raw);
    const cmd = (obj.tool_input || {}).command || '';
    if (!cmd || !NOISY_PATTERNS.some(p => p.test(cmd))) { process.exit(0); }
    const out = JSON.parse(JSON.stringify(obj));
    out.tool_input.command = wrap(cmd);
    process.stdout.write(JSON.stringify(out));
    process.exit(0);
  } catch { process.exit(0); }
});
HOOK

# ── 4. Write audit-surface PreToolUse session-start hook ─────────────────────
echo "[4a/6] Writing audit-surface hook..."
cp "$REPO_DIR/scripts/hooks/audit-surface.js" "$HOOKS_DIR/audit-surface.js"

# ── 4c. Copy Web App pull/push hooks + MCP server ────────────────────────────
echo "[4c/6] Copying webapp-pull + webapp-push hooks and MCP server..."
cp "$REPO_DIR/scripts/hooks/webapp-pull.sh" "$HOOKS_DIR/webapp-pull.sh"
cp "$REPO_DIR/scripts/hooks/webapp-push.sh" "$HOOKS_DIR/webapp-push.sh"
chmod +x "$HOOKS_DIR/webapp-pull.sh" "$HOOKS_DIR/webapp-push.sh"

mkdir -p "$CLAUDE_DIR/mcp"
cp "$REPO_DIR/scripts/mcp-server/team-workspace-mcp.js" "$CLAUDE_DIR/mcp/team-workspace-mcp.js"
echo "  installed: ~/.claude/mcp/team-workspace-mcp.js"

# ── 4b. Write truncate-bash-output PostToolUse safety-net ─────────────────────
echo "[4b/6] Writing truncate-bash-output hook..."
cat > "$HOOKS_DIR/truncate-bash-output.js" << 'HOOK'
#!/usr/bin/env node
// PostToolUse safety-net: truncates any Bash output over 8000 chars to its tail.
const MAX = 8000;
let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  try {
    const obj = JSON.parse(raw);
    const out = obj.output || obj.content || '';
    if (typeof out === 'string' && out.length > MAX) {
      obj.output = `[...${out.length - MAX} chars omitted]\n${out.slice(-MAX)}`;
      process.stdout.write(JSON.stringify(obj));
    } else {
      process.stdout.write(raw);
    }
  } catch { process.stdout.write(raw); }
  process.exit(0);
});
HOOK

# ── 5. Wire hooks into ~/.claude/settings.json ────────────────────────────────
echo "[5/6] Writing settings.json..."
SETTINGS="$CLAUDE_DIR/settings.json"
# Merge with any existing top-level keys (preserve includeCoAuthoredBy etc.)
python3 - "$SETTINGS" << 'PY'
import json, sys, os
path = sys.argv[1]
existing = {}
if os.path.exists(path):
    try:
        with open(path) as f: existing = json.load(f)
    except: pass

existing.setdefault("includeCoAuthoredBy", False)
h = os.path.expanduser('~')
clv2 = f"{h}/.claude/skills/continuous-learning-v2/hooks/observe.sh"
existing["hooks"] = {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": f"bash {h}/.claude/hooks/webapp-pull.sh",
          "description": "Session-start: pull team memory + instincts from Apps Script cache API (once per session)"
        },
        {
          "type": "command",
          "command": f"node {h}/.claude/hooks/audit-surface.js",
          "description": "Session-start: surface stale audit or critical agent-audit findings (fires once per OS session)"
        },
        {
          "type": "command",
          "command": f"node {h}/.claude/hooks/quiet-noisy-commands.js",
          "description": "Rewrite noisy install/build/test commands to emit only errors, failures, and summary"
        }
      ]
    },
    {
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": f"CLAUDE_CODE_ENTRYPOINT=cli {clv2} pre",
        "description": "Continuous learning: capture pre-tool observations for instinct extraction"
      }]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": f"node {h}/.claude/hooks/truncate-bash-output.js",
        "description": "Safety-net: truncate any Bash output still over 8000 chars to its tail"
      }]
    },
    {
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": f"CLAUDE_CODE_ENTRYPOINT=cli {clv2} post",
        "description": "Continuous learning: capture post-tool observations for instinct extraction"
      }]
    }
  ],
  "Stop": [
    {
      "hooks": [{
        "type": "command",
        "command": f"bash {h}/.claude/hooks/webapp-push.sh",
        "description": "Session-end: push cost row to Apps Script cache API"
      }]
    }
  ]
}
existing.setdefault("mcpServers", {})
existing["mcpServers"]["ecc-team-workspace"] = {
    "command": "node",
    "args": [f"{h}/.claude/mcp/team-workspace-mcp.js"],
    "description": "ECC Team Workspace — team_health, team_pull, team_write_cost, team_write_memory, team_write_instinct, team_write_audit, team_invalidate"
}
with open(path, 'w') as f: json.dump(existing, f, indent=2)
print(f"  wrote {path}")
PY

# ── 6. Set agent model assignments ────────────────────────────────────────────
echo "[6/6] Setting agent model assignments..."

# Haiku — mechanical/pattern-matching agents (fast, cheap, no deep reasoning needed)
HAIKU_AGENTS=(
  refactor-cleaner      # runs knip/depcheck, removes dead code
  code-simplifier       # mechanical simplification passes
  type-design-analyzer  # structural type shape analysis
  pr-test-analyzer      # coverage counting and gap detection
  agent-evaluator       # rubric scoring against a fixed 5-axis scale
  opensource-sanitizer  # regex pattern scanning for secrets/PII
)

# Sonnet — was opus (over-specified; these need reasoning but not max depth)
SONNET_DOWNGRADE=(
  architect
  healthcare-reviewer
  planner
  spec-miner
)

apply_model() {
  local model="$1" name="$2"
  for dir in "$CLAUDE_DIR/agents" "$REPO_DIR/agents"; do
    local f="$dir/$name.md"
    if [ -f "$f" ]; then
      sed -i "s/^model: .*/model: $model/" "$f"
      echo "  $model: $name"
    fi
  done
}

for name in "${HAIKU_AGENTS[@]}"; do  apply_model haiku  "$name"; done
for name in "${SONNET_DOWNGRADE[@]}"; do apply_model sonnet "$name"; done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Setup complete."
echo ""
RULE_FILES=$(find "$CLAUDE_DIR/rules/" -name "*.md" 2>/dev/null | wc -l)
RULE_TOK=$(find "$CLAUDE_DIR/rules/" -name "*.md" -exec wc -c {} \; 2>/dev/null | awk '{s+=$1} END {print int(s/4)}')
AGENT_COUNT=$(ls "$CLAUDE_DIR/agents/"*.md 2>/dev/null | wc -l)
HAIKU_COUNT=$(grep -l "^model: haiku" "$CLAUDE_DIR/agents/"*.md 2>/dev/null | wc -l)
SONNET_COUNT=$(grep -l "^model: sonnet" "$CLAUDE_DIR/agents/"*.md 2>/dev/null | wc -l)
echo "  Rules:  $RULE_FILES files (~$RULE_TOK tokens)"
echo "  Agents: $AGENT_COUNT total — haiku: $HAIKU_COUNT, sonnet: $SONNET_COUNT, opus: 0"
echo "  Hooks:  webapp-pull (PreToolUse/Bash) + quiet-noisy-commands (PreToolUse/Bash) + truncate-bash-output (PostToolUse/Bash) + webapp-push (Stop)"
echo ""
echo "To add a language rule pack later:"
echo "  bash scripts/setup-optimized.sh typescript"
