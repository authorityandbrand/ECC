#!/usr/bin/env node
// PreToolUse hook: surfaces stale or critical agent audit findings at session start.
// Fires once per session (tracks via /tmp flag file). Fast — reads one file, no network.
// If audit file is missing or >24h old, prints a reminder to stderr.
// If audit has critical action items, prints them to stderr.

const fs = require('fs');
const path = require('path');
const os = require('os');

const AUDIT_FILE = path.join(os.homedir(), '.claude', 'audit', 'agent-audit.md');
const SESSION_FLAG = path.join(os.tmpdir(), `ecc-audit-surfaced-${process.env.USER || 'claude'}`);
const STALE_MS = 24 * 60 * 60 * 1000; // 24 hours

let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  try {
    // Only fire once per OS session
    if (fs.existsSync(SESSION_FLAG)) { process.exit(0); }
    fs.writeFileSync(SESSION_FLAG, Date.now().toString());

    if (!fs.existsSync(AUDIT_FILE)) {
      process.stderr.write(
        '[agent-auditor] No audit file found. Run the agent-auditor agent to generate ~/.claude/audit/agent-audit.md\n'
      );
      process.exit(0);
    }

    const stat = fs.statSync(AUDIT_FILE);
    const ageMs = Date.now() - stat.mtimeMs;
    const content = fs.readFileSync(AUDIT_FILE, 'utf8');

    // Extract "Generated:" timestamp line
    const genMatch = content.match(/^Generated:\s*(.+)$/m);
    const genStr = genMatch ? genMatch[1].trim() : 'unknown';

    if (ageMs > STALE_MS) {
      const hours = Math.round(ageMs / 3600000);
      process.stderr.write(
        `[agent-auditor] Audit is ${hours}h old (generated: ${genStr}). Re-run agent-auditor to refresh.\n`
      );
    }

    // Surface critical action items section if present
    const critMatch = content.match(/## Critical Action Items\n([\s\S]*?)(?=\n##|$)/);
    if (critMatch) {
      const items = critMatch[1].trim();
      if (items && items !== 'None' && !items.startsWith('_None')) {
        const lines = items.split('\n').filter(l => l.trim()).slice(0, 3);
        process.stderr.write(`[agent-auditor] Critical items from last audit:\n`);
        lines.forEach(l => process.stderr.write(`  ${l.trim()}\n`));
      }
    }
  } catch {
    // Never block on audit errors
  }
  process.exit(0);
});
