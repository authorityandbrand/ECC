---
description: Sync with ECC team workspace — pull shared memory/instincts at session start, push cost/findings at session end.
---

# Team Sync Command

Connects the current session to the shared ECC Team Workspace in Google Drive and Google Sheets.
Run `/team-sync pull` at session start and `/team-sync push` at session end.

## Usage

```
/team-sync pull    # load shared memory + instincts from team workspace
/team-sync push    # write session cost, new memory, and instincts to team workspace
/team-sync audit   # upload latest agent-audit.md to team Drive audit folder
/team-sync agents  # export current ~/.claude/agents/ snapshot to team Drive agents folder
```

## Skill Reference

Load `team-workspace` skill before executing — it contains all Drive folder IDs,
Sheet ID, tab schemas, and GWS call patterns.

## Pull (session start)

**Goal:** Orient the session with team-shared knowledge before starting work.

### Step 1 — Load memory entries

```
mcp__Legal_API__gws path=sheets.spreadsheets.values.get
params: {
  "spreadsheetId": "16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY",
  "range": "memory_entries!A2:F",
  "majorDimension": "ROWS"
}
```

Filter for rows where scope matches the current project (col B = project name from `git remote get-url origin`).
Summarize relevant entries for the user: "Team memory: N entries loaded. Key items: ..."

### Step 2 — Load instincts

```
params: { "range": "instincts!A2:F" }
```

Display the 5 most recent instincts (sorted by col F = created_at desc).
These are behavioral patterns extracted from previous sessions across the team.

### Step 3 — Check agent sync

Run `bash scripts/sync-agents.sh` to compare installed agents against repo versions.
Report any agents that are out of sync. Do NOT auto-fix — report only.

### Step 4 — Report

```
TEAM SYNC: pull complete
═══════════════════════
Memory entries loaded:  N (project-scoped)
Instincts loaded:       N
Agent drift detected:   [none | list of diverged agents]
Ready. Team context is live.
```

## Push (session end)

**Goal:** Write this session's cost, learnings, and any new memory to the shared workspace.

### Step 1 — Append cost log row

Collect values:
- `date`: today's date (ISO format)
- `user`: `git config user.email` or `$USER`
- `project`: repo name from `git remote get-url origin` (last path segment, no .git)
- `session_id`: from `CLAUDE_SESSION_ID` env var or generate a short UUID
- `model_tier`: dominant tier used this session (haiku/sonnet/sonnet-deep)
- `tokens_in`, `tokens_out`, `cost_usd`: from `~/.claude/cost-tracker/latest.json` if it exists, else ask user to estimate or leave blank
- `agent_name`: primary agent used (or "orchestrator" if multiple)
- `task_summary`: one-line description of what was accomplished

```
mcp__Legal_API__gws path=sheets.spreadsheets.values.append
params: {
  "spreadsheetId": "16fRezVWzx5KVk3zkdHcMgLl1qrVAPoflkjuxgBfVewY",
  "range": "cost_log!A:J",
  "valueInputOption": "RAW",
  "insertDataOption": "INSERT_ROWS"
}
json_body: { "values": [[date, user, project, session_id, model_tier, tokens_in, tokens_out, cost_usd, agent_name, task_summary]] }
```

### Step 2 — Push new memory entries (if any)

If this session produced reusable findings worth sharing with the team (architectural decisions,
gotchas, patterns that will recur), append them to `memory_entries`:

```
json_body: { "values": [[uuid, "project", "tag", "content", user, iso_timestamp]] }
```

Only push entries that are genuinely reusable. Do not push task-specific ephemera.

### Step 3 — Push new instincts (if any)

If Continuous Learning produced new instincts this session (`~/.local/share/ecc-homunculus/`),
summarize the top 3 and append to `instincts` tab:

```
json_body: { "values": [[uuid, pattern, context, confidence_0_to_1, user, iso_timestamp]] }
```

### Step 4 — Confirm

```
TEAM SYNC: push complete
════════════════════════
Cost row appended:      ✓
Memory entries pushed:  N
Instincts pushed:       N
```

## Audit Upload (`/team-sync audit`)

Reads `~/.claude/audit/agent-audit.md` and uploads it to the Drive audit folder.

```
mcp__Google_Drive__create_file
  title: "agent-audit-YYYY-MM-DD.md"
  parentId: "1zmtFspK2xR6SrVuro25BMELWLp1T8GUF"
  contentMimeType: "text/plain"
  textContent: <contents of ~/.claude/audit/agent-audit.md>
  disableConversionToGoogleType: true
```

## Agent Export (`/team-sync agents`)

Exports a snapshot of all installed agents to Drive for non-git team members.
Creates a single JSON index file listing all agents with name, description, model, tools.

```
mcp__Google_Drive__create_file
  title: "agents-snapshot-YYYY-MM-DD.json"
  parentId: "1vaAGaitA9ccmnFtJ7mcp8ywdz7zDwBPY"
  contentMimeType: "application/json"
  disableConversionToGoogleType: true
  textContent: <JSON array of agent metadata>
```

## Notes

- This command is agent-invoked only. Shell hooks cannot reach Drive/Sheets MCP tools.
- Always run pull before push — never push stale data from a prior session.
- If Sheets returns 429 (rate limit), wait 2s and retry once.
- The skill `team-workspace` has all IDs and exact call patterns if you need to debug.
