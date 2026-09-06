#!/usr/bin/env node
'use strict';
// ECC Team Workspace MCP Server (stdio)
// Wraps the Apps Script Web App as native MCP tools for Claude Code sessions.
// Reads ECC_WEBAPP_URL and ECC_WEBAPP_TOKEN from ~/.ecc/team-workspace.env.
//
// Install: add to ~/.claude/settings.json mcpServers (see mcp-configs/mcp-servers.json)
//   "ecc-team-workspace": { "command": "node", "args": ["~/.claude/mcp/team-workspace-mcp.js"] }
//
// Tools exposed: team_health, team_pull, team_write_cost, team_write_memory,
//                team_write_instinct, team_write_audit, team_invalidate

const https    = require('https');
const http     = require('http');
const fs       = require('fs');
const path     = require('path');
const readline = require('readline');

// ── Load ~/.ecc/team-workspace.env ─────────────────────────────────────────────
(function loadEnv() {
  const f = path.join(process.env.HOME || '', '.ecc', 'team-workspace.env');
  if (!fs.existsSync(f)) return;
  for (const line of fs.readFileSync(f, 'utf8').split('\n')) {
    const m = line.match(/^export\s+([A-Z_][A-Z_0-9]*)="?([^"]*)"?/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
})();

const WEBAPP_URL   = process.env.ECC_WEBAPP_URL   || '';
const WEBAPP_TOKEN = process.env.ECC_WEBAPP_TOKEN || '';

// ── HTTP helper (follows redirects) ────────────────────────────────────────────
function httpRequest(method, urlStr, body, hops) {
  hops = hops || 0;
  return new Promise((resolve, reject) => {
    if (hops > 5) return reject(new Error('too many redirects'));
    const url = new URL(urlStr);
    const mod = url.protocol === 'https:' ? https : http;
    const opts = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method,
      headers: method === 'POST' ? { 'Content-Type': 'application/json' } : {}
    };
    const req = mod.request(opts, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return resolve(httpRequest('GET', res.headers.location, null, hops + 1));
      }
      let data = '';
      res.on('data', d => { data += d; });
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch { resolve({ _raw: data }); }
      });
    });
    req.on('error', reject);
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

function webappGet(params) {
  if (!WEBAPP_URL) return Promise.reject(new Error('ECC_WEBAPP_URL not configured — source ~/.ecc/team-workspace.env'));
  const u = new URL(WEBAPP_URL);
  u.searchParams.set('token', WEBAPP_TOKEN);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, String(v));
  return httpRequest('GET', u.toString(), null);
}

function webappPost(body) {
  if (!WEBAPP_URL) return Promise.reject(new Error('ECC_WEBAPP_URL not configured — source ~/.ecc/team-workspace.env'));
  body.token = WEBAPP_TOKEN;
  return httpRequest('POST', WEBAPP_URL, body);
}

// ── Tool definitions ───────────────────────────────────────────────────────────
const TOOLS = [
  {
    name: 'team_health',
    description: 'Check ECC team workspace status — Web App reachable, sheet ID stored, BQ project.',
    inputSchema: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'team_pull',
    description: 'Pull team memory entries and instincts for the current project. Use at session start to load shared context.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Project name to scope memory (optional, defaults to global)' }
      }
    }
  },
  {
    name: 'team_write_cost',
    description: 'Log a session cost row to the shared cost tracking sheet and BigQuery ecc_team.cost_log.',
    inputSchema: {
      type: 'object',
      properties: {
        project:      { type: 'string', description: 'Project or repo name' },
        model_tier:   { type: 'string', description: 'haiku | sonnet | opus' },
        tokens_in:    { type: 'number' },
        tokens_out:   { type: 'number' },
        cost_usd:     { type: 'number' },
        agent_name:   { type: 'string' },
        task_summary: { type: 'string' },
        session_id:   { type: 'string' },
        user:         { type: 'string' }
      },
      required: ['project', 'model_tier']
    }
  },
  {
    name: 'team_write_memory',
    description: 'Write a shared memory entry (Sheets + BQ). Use to persist cross-session knowledge for the team.',
    inputSchema: {
      type: 'object',
      properties: {
        tag:     { type: 'string', description: 'Short retrieval label, e.g. "arch-decision", "api-pattern"' },
        content: { type: 'string', description: 'Memory content to store' },
        scope:   { type: 'string', description: 'project | team | global (default: team)' },
        author:  { type: 'string', description: 'Agent or user that created this entry' }
      },
      required: ['tag', 'content']
    }
  },
  {
    name: 'team_write_instinct',
    description: 'Write a learned instinct or behavioral pattern to the team instincts store (Sheets + BQ).',
    inputSchema: {
      type: 'object',
      properties: {
        pattern:     { type: 'string', description: 'The pattern, rule, or heuristic learned' },
        context:     { type: 'string', description: 'When and where this pattern applies' },
        confidence:  { type: 'number', description: '0.0–1.0 confidence score' },
        source_user: { type: 'string', description: 'Agent or user that derived this instinct' }
      },
      required: ['pattern', 'context']
    }
  },
  {
    name: 'team_write_audit',
    description: 'Write an agent audit finding to the shared audit history (Sheets + BQ).',
    inputSchema: {
      type: 'object',
      properties: {
        agent_name: { type: 'string' },
        tier:       { type: 'string', description: 'haiku | sonnet | opus' },
        gap_type:   { type: 'string', description: 'e.g. tool-mismatch, model-over-spec, coverage-gap' },
        severity:   { type: 'string', description: 'CRITICAL | HIGH | MEDIUM | LOW' },
        finding:    { type: 'string', description: 'Description of the finding' },
        resolved:   { type: 'boolean' }
      },
      required: ['agent_name', 'finding', 'severity']
    }
  },
  {
    name: 'team_invalidate',
    description: 'Invalidate CacheService entries in the Web App, forcing a fresh Sheets read on the next pull.',
    inputSchema: {
      type: 'object',
      properties: {
        key: { type: 'string', description: 'Specific cache key to clear, or omit to clear all pull caches' }
      }
    }
  }
];

// ── Tool executor ──────────────────────────────────────────────────────────────
async function callTool(name, args) {
  switch (name) {
    case 'team_health':
      return webappGet({ action: 'health' });

    case 'team_pull':
      return webappGet({ action: 'pull', ...(args.project ? { project: args.project } : {}) });

    case 'team_write_cost':
      return webappPost({
        action: 'cost',
        date: new Date().toISOString(),
        user: args.user || process.env.USER || '',
        project: args.project || '',
        session_id: args.session_id || '',
        model_tier: args.model_tier || 'sonnet',
        tokens_in: args.tokens_in || 0,
        tokens_out: args.tokens_out || 0,
        cost_usd: args.cost_usd || 0,
        agent_name: args.agent_name || '',
        task_summary: args.task_summary || ''
      });

    case 'team_write_memory':
      return webappPost({
        action: 'memory_write',
        scope: args.scope || 'team',
        tag: args.tag || '',
        content: args.content || '',
        author: args.author || ''
      });

    case 'team_write_instinct':
      return webappPost({
        action: 'instinct_write',
        pattern: args.pattern || '',
        context: args.context || '',
        confidence: args.confidence || 0.8,
        source_user: args.source_user || ''
      });

    case 'team_write_audit':
      return webappPost({
        action: 'audit',
        agent_name: args.agent_name || '',
        tier: args.tier || '',
        gap_type: args.gap_type || '',
        severity: args.severity || 'LOW',
        finding: args.finding || '',
        resolved: args.resolved || false
      });

    case 'team_invalidate':
      return webappPost({ action: 'invalidate', ...(args.key ? { key: args.key } : {}) });

    default:
      throw new Error('Unknown tool: ' + name);
  }
}

// ── MCP stdio server (JSON-RPC 2.0) ───────────────────────────────────────────
const rl = readline.createInterface({ input: process.stdin, terminal: false });

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

rl.on('line', async (line) => {
  line = line.trim();
  if (!line) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }

  const { id, method, params } = msg;

  if (method === 'initialize') {
    send({ jsonrpc: '2.0', id, result: {
      protocolVersion: '2024-11-05',
      capabilities: { tools: {} },
      serverInfo: { name: 'ecc-team-workspace', version: '1.0.0' }
    }});
    return;
  }

  if (method === 'initialized') return;

  if (method === 'tools/list') {
    send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    return;
  }

  if (method === 'tools/call') {
    const toolName = (params || {}).name;
    const toolArgs = (params || {}).arguments || {};
    try {
      const result = await callTool(toolName, toolArgs);
      send({ jsonrpc: '2.0', id, result: {
        content: [{ type: 'text', text: JSON.stringify(result, null, 2) }]
      }});
    } catch (err) {
      send({ jsonrpc: '2.0', id, result: {
        content: [{ type: 'text', text: 'Error: ' + err.message }],
        isError: true
      }});
    }
    return;
  }

  if (id !== undefined) {
    send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Method not found: ' + method } });
  }
});

process.stdin.on('end', () => process.exit(0));
