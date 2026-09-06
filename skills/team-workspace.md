# Team Workspace Skill

Reference skill for ECC team-shared infrastructure. Load before writing any command or script
that reads from or writes to the shared Google Drive workspace or Cost Tracking Sheet.

## Configuration

IDs are stored in `~/.ecc/team-workspace.env` (not in source control).
Load it at runtime:

```bash
source ~/.ecc/team-workspace.env
# Exports: ECC_DRIVE_ROOT, ECC_DRIVE_AGENTS, ECC_DRIVE_MEMORY,
#          ECC_DRIVE_COST_LOGS, ECC_DRIVE_AUDIT, ECC_DRIVE_INSTINCTS,
#          ECC_SHEETS_COST_ID, ECC_GWS_ACCOUNT
```

To initialize for a new team member, run:
```bash
bash scripts/init-team-workspace.sh
```
This script interactively prompts for the Drive folder IDs and writes `~/.ecc/team-workspace.env`.
Existing members share the IDs out-of-band (Slack DM, 1Password shared vault, etc.).

## Drive Workspace Structure

```
ECC-Team-Workspace/               $ECC_DRIVE_ROOT
  ├── agents/                     $ECC_DRIVE_AGENTS
  ├── memory/                     $ECC_DRIVE_MEMORY
  ├── cost-logs/                  $ECC_DRIVE_COST_LOGS
  │   └── ECC Cost Tracking       $ECC_SHEETS_COST_ID  (Google Sheet)
  ├── audit/                      $ECC_DRIVE_AUDIT
  └── instincts/                  $ECC_DRIVE_INSTINCTS
```

## Cost Tracking Sheet — Tab Schema

Sheet ID loaded from `$ECC_SHEETS_COST_ID`.

| Tab | Columns |
|-----|---------|
| `cost_log` | date, user, project, session_id, model_tier, tokens_in, tokens_out, cost_usd, agent_name, task_summary |
| `memory_entries` | id, scope, tag, content, author, created_at |
| `instincts` | id, pattern, context, confidence, source_user, created_at |
| `audit_history` | run_date, agent_name, tier, gap_type, severity, finding, resolved |
| `agent_scores` | date, agent_name, task_type, accuracy, completeness, clarity, actionability, score |

## How to Read from Sheets (GWS)

```
mcp__Legal_API__gws path=sheets.spreadsheets.values.get
params: {
  "spreadsheetId": "$ECC_SHEETS_COST_ID",
  "range": "memory_entries!A2:F",
  "majorDimension": "ROWS"
}
```

## How to Append a Row to Sheets (GWS)

```
mcp__Legal_API__gws path=sheets.spreadsheets.values.append
params: {
  "spreadsheetId": "$ECC_SHEETS_COST_ID",
  "range": "cost_log!A:J",
  "valueInputOption": "RAW",
  "insertDataOption": "INSERT_ROWS"
}
json_body: { "values": [[date, user, project, session_id, model_tier, tokens_in, tokens_out, cost_usd, agent_name, task_summary]] }
```

## How to Upload a File to Drive

```
mcp__Google_Drive__create_file
  title: "agent-audit-YYYY-MM-DD.md"
  parentId: "$ECC_DRIVE_AUDIT"
  contentMimeType: "text/plain"
  textContent: <file contents>
  disableConversionToGoogleType: true
```

## How to List Files in a Folder

```
mcp__Legal_API__gws path=drive.files.list
params: {
  "q": "'$ECC_DRIVE_MEMORY' in parents and trashed = false",
  "fields": "files(id,name,modifiedTime)",
  "orderBy": "modifiedTime desc"
}
```

## Constraints

- **MCP only**: Drive and GWS are only accessible from within a Claude Code agent session.
  Shell hooks cannot call these tools — all sync must be agent-invoked (slash commands).
- **BigQuery**: `mcp__Legal_API__run_bigquery` is read-only. Cannot create new datasets.
  Use Sheets for structured team data. BigQuery write access = future upgrade path.
- **Cloudflare D1**: No MCP tools or wrangler CLI available. Future fast-cache upgrade path.

## Cost Estimation (Sheets-based cache)

| Operation | Latency | Notes |
|-----------|---------|-------|
| Read 50 memory rows | ~150ms | Single API call via GWS |
| Append 1 cost row | ~100ms | Append, not overwrite |
| Upload audit MD file | ~200ms | Drive API |
| Full session-start sync | ~400ms | Memory + instincts in parallel |

## Agent Versioning

Canonical agent definitions: **repo** `ECC/agents/*.md` (git, source of truth).
Installed agents: `~/.claude/agents/*.md`.

`scripts/sync-agents.sh` diffs the two and reports divergence.
Run after `git pull` or call `/team-sync pull` (runs it automatically).

The Drive `agents/` folder stores exported snapshots for non-git team members —
not the source of truth.
