# Team Workspace Skill

Reference skill for ECC team-shared infrastructure. Load before writing any command or script
that reads from or writes to the shared Google Drive workspace or Cost Tracking Sheet.

## Drive Workspace (authorityandbrand@gmail.com)

```
ECC-Team-Workspace/               root:       1il04nQKRFc-gYgmvO5de0PMKpFVEv2Oh
  ├── agents/                     agents:     1vaAGaitA9ccmnFtJ7mcp8ywdz7zDwBPY
  ├── memory/                     memory:     14iVC7OLrDoQ9ZbAz5VpZ-GLbZ9VoaqmZ
  ├── cost-logs/                  cost_logs:  1Y0_a65zSNP8UYXpsFn0Sj6Zpxi8wAAdU
  │   └── ECC Cost Tracking       sheet:      16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY
  ├── audit/                      audit:      1zmtFspK2xR6SrVuro25BMELWLp1T8GUF
  └── instincts/                  instincts:  1WBJclsVzvIBxjHHAmQwgmCa_6mW-WWdz
```

## Cost Tracking Sheet — Tab Schema

Sheet ID: `16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY`

| Tab | Columns |
|-----|---------|
| `cost_log` | date, user, project, session_id, model_tier, tokens_in, tokens_out, cost_usd, agent_name, task_summary |
| `memory_entries` | id, scope, tag, content, author, created_at |
| `instincts` | id, pattern, context, confidence, source_user, created_at |
| `audit_history` | run_date, agent_name, tier, gap_type, severity, finding, resolved |
| `agent_scores` | date, agent_name, task_type, accuracy, completeness, clarity, actionability, score |

## How to Read from Sheets (GWS)

```
path: sheets.spreadsheets.values.get
params: {
  "spreadsheetId": "16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY",
  "range": "memory_entries!A2:F",
  "majorDimension": "ROWS"
}
```

## How to Append a Row to Sheets (GWS)

```
path: sheets.spreadsheets.values.append
params: {
  "spreadsheetId": "16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY",
  "range": "cost_log!A:J",
  "valueInputOption": "RAW",
  "insertDataOption": "INSERT_ROWS"
}
json_body: {
  "values": [["2026-09-06", "jim", "ECC", "session_abc", "sonnet", 12000, 3000, 0.045, "code-reviewer", "reviewed auth module"]]
}
```

## How to Upload a File to Drive (GWS)

```
path: drive.files.create
params: {"fields": "id,name"}
json_body: {
  "name": "agent-audit-2026-09-06.md",
  "parents": ["1zmtFspK2xR6SrVuro25BMELWLp1T8GUF"],
  "mimeType": "text/plain"
}
```
Use `mcp__Google_Drive__create_file` with `parentId` for simpler uploads.

## How to List Files in a Folder

```
path: drive.files.list
params: {
  "q": "'14iVC7OLrDoQ9ZbAz5VpZ-GLbZ9VoaqmZ' in parents and trashed = false",
  "fields": "files(id,name,modifiedTime)",
  "orderBy": "modifiedTime desc"
}
```

## Constraints

- **MCP only**: Drive and GWS are only accessible from within a Claude Code agent session.
  Shell hooks cannot call these tools — all sync must be agent-invoked (slash commands).
- **Account**: authorityandbrand@gmail.com only. The Legal API GWS tool uses the same account.
- **BigQuery**: `mcp__Legal_API__run_bigquery` is read-only against the legal_case dataset.
  Cannot create new datasets or tables via current credentials. Use Sheets for structured data.
- **Cloudflare D1**: No MCP tools or wrangler CLI available. Future upgrade path.

## Cost Estimation (Sheets-based cache)

| Operation | Latency | Notes |
|-----------|---------|-------|
| Read 50 memory rows | ~150ms | Single API call via GWS |
| Append 1 cost row | ~100ms | Append, not overwrite |
| Upload audit MD file | ~200ms | Drive API |
| Full session-start sync | ~400ms | Memory + instincts in parallel |

## Agent Versioning

Canonical agent definitions live in the **repo** at `ECC/agents/*.md`.
Installed agents live at `~/.claude/agents/*.md`.

`scripts/sync-agents.sh` diffs the two and warns on divergence.
Run it after `git pull` or call `/team-sync pull` which runs it automatically.

The Drive `agents/` folder stores **exported snapshots** for non-git team members —
not the source of truth. Git is the source of truth for agent definitions.
