#!/usr/bin/env node
/**
 * generate-opencode-config.js
 *
 * Generates opencode.json from:
 *   - opencode-base.json (agent definitions WITHOUT permission blocks)
 *   - permission-templates.json (7 shared permission patterns)
 *   - agent-overrides.json (agent-specific extra properties: hidden, custom perms)
 *
 * Usage:
 *   node scripts/lib/generate-opencode-config.js           # write opencode.json
 *   node scripts/lib/generate-opencode-config.js --validate # compare only, exit 1 on diff
 *
 * WHY: The original opencode.json had ~1,710 duplicated lines (73% of file)
 * because the same permission block was copied across 22 agents. This generator
 * maintains a single source of truth in permission-templates.json.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const BASE_PATH = path.join(__dirname, 'opencode-base.json');
const TEMPLATES_PATH = path.join(__dirname, 'permission-templates.json');
const OVERRIDES_PATH = path.join(__dirname, 'agent-overrides.json');
const OUTPUT_PATH = path.join(ROOT, 'opencode.json');

const VALIDATE = process.argv.includes('--validate');

// --- Role keywords for auto-registration (checked when not in explicit map) ---
// Mirrors $RoleKeywords in scripts/lib/template-detection.ps1
const ROLE_KEYWORDS = {
  security:    'readonly',
  infra:       'readonly',
  docs:        'readonly',
  seo:         'readonly',
  frontend:    'readonly',
  performance: 'readonly',
  datascience: 'readonly',
  reviewer:    'reviewer',
  vMK:         'orchestrator',
};

// --- Detect template for an agent name ---
// Resolution order (must mirror Detect-Template in template-detection.ps1 exactly):
//   1. Explicit lookup in TEMPLATE_MAP (SSOT anchor)
//   2. Suffix auto-registration (-sub-auto → auto-sub, -semi → semi, -auto → auto, -sub → recurse)
//   3. Role keyword matching
//   4. Fail-closed — throw
function detectTemplate(agentName) {
  // 1. Explicit lookup — SSOT anchor, always wins
  if (TEMPLATE_MAP[agentName]) {
    return TEMPLATE_MAP[agentName];
  }

  // 2. Suffix auto-registration (longest suffix first)
  if (agentName.endsWith('-sub-auto')) return 'auto-sub';
  if (agentName.endsWith('-semi'))      return 'semi';
  if (agentName.endsWith('-auto'))     return 'auto';
  if (agentName.endsWith('-sub'))      return detectTemplate(agentName.slice(0, -4));

  // 3. Role keyword matching
  for (const [keyword, template] of Object.entries(ROLE_KEYWORDS)) {
    if (agentName.includes(keyword)) {
      return template;
    }
  }

  // 4. Fail-closed
  throw new Error(`No template mapping found for agent '${agentName}'. Add explicit entry to TEMPLATE_MAP or follow naming conventions.`);
}

// --- Agent-to-template mapping (SSOT anchor) ---
// ALL agents should be listed here. New agents following naming conventions are auto-detected.
const TEMPLATE_MAP = {
  // Orchestrator — full bash allow + extra language denials
  'gentleman-vMK': 'orchestrator',
  'gentle-orchestrator': 'sddorchestrator',

  // Read-only specialists — bash deny, no write/edit
  'gentleman-security': 'readonly',
  'gentleman-seo': 'readonly',
  'gentleman-infra': 'readonly',
  'gentleman-frontend': 'readonly',
  'gentleman-performance': 'readonly',
  'gentleman-datascience': 'readonly',
  'gentleman-docs': 'readonly',

  // Read/write agents — bash ask, full edit/write with deny rules
  'gentleman-deep': 'readwrite',
  'gentleman-quick': 'readwrite',
  'gentleman-codex': 'readwrite',
  'gentleman-implementer': 'readwrite',
  'sdd-apply': 'readwrite',
  'sdd-archive': 'readwrite',
  'sdd-design': 'readwrite',
  'sdd-explore': 'readwrite',
  'sdd-init': 'readwrite',
  'sdd-orchestrator': 'sddorchestrator',
  'sdd-propose': 'readwrite',
  'sdd-spec': 'readwrite',
  'sdd-tasks': 'readwrite',
  'sdd-verify': 'readwrite',

  // Subagent twins (mode: subagent, delegable via Task tool) — mirror primary templates
  'gentleman-deep-sub': 'readwrite',
  'gentleman-quick-sub': 'readwrite',
  'gentleman-implementer-sub': 'readwrite',
  'gentleman-codex-sub': 'readwrite',
  'gentleman-security-sub': 'readonly',

  // Read-only specialist twins — delegable via Task tool (previously ⚠️ fallback to general)
  'gentleman-seo-sub': 'readonly',
  'gentleman-infra-sub': 'readonly',
  'gentleman-frontend-sub': 'readonly',
  'gentleman-performance-sub': 'readonly',
  'gentleman-datascience-sub': 'readonly',
  'gentleman-docs-sub': 'readonly',

  // Mode variants — AUTO (all auto-approve except push + destructive + network)
  'gentleman-vMK-auto': 'auto',
  'gentleman-deep-auto': 'auto',
  'gentleman-quick-auto': 'auto',
  'gentleman-codex-auto': 'auto',
  'gentleman-implementer-auto': 'auto',

  // Mode variants — AUTO subagent twins (zero-ask, delegable via Task tool in auto mode)
  'gentleman-deep-sub-auto': 'auto-sub',
  'gentleman-quick-sub-auto': 'auto-sub',
  'gentleman-codex-sub-auto': 'auto-sub',
  'gentleman-implementer-sub-auto': 'auto-sub',

  // Mode variants — SEMI (safe commands auto, writes/commits ask)
  'gentleman-vMK-semi': 'semi',
  'gentleman-deep-semi': 'semi',
  'gentleman-quick-semi': 'semi',
  'gentleman-codex-semi': 'semi',
  'gentleman-implementer-semi': 'semi',

  // Independent evaluator — bash ask, no edit/write
  'gentleman-reviewer': 'reviewer',
  'gentleman-reviewer-sub': 'reviewer',
};

// --- Permission key order (must match original file) ---
// Standard: bash→edit→read→write
// sdd-orchestrator: bash→delegate→delegation_list→delegation_read→edit→read→write→task
const STANDARD_PERM_ORDER = ['bash', 'edit', 'read', 'write'];
const SDD_ORCH_PERM_ORDER = ['bash', 'delegate', 'delegation_list', 'delegation_read', 'edit', 'read', 'write', 'task'];

// --- Load inputs ---
console.log('[1/5] Loading base config, templates, and overrides...');
const base = JSON.parse(fs.readFileSync(BASE_PATH, 'utf8'));
const templates = JSON.parse(fs.readFileSync(TEMPLATES_PATH, 'utf8'));

let overrides = {};
try {
  overrides = JSON.parse(fs.readFileSync(OVERRIDES_PATH, 'utf8'));
} catch (e) {
  console.log('  No agent-overrides.json found, using empty overrides');
}

// --- Deep clone and sort keys in permission objects ---
function sortPermKeys(perm, agentName) {
  // Use agent-specific key order if available, otherwise standard
  const keyOrder = (agentName === 'sdd-orchestrator' || agentName === 'gentle-orchestrator') ? SDD_ORCH_PERM_ORDER : STANDARD_PERM_ORDER;
  const sorted = {};
  for (const key of keyOrder) {
    if (perm[key] !== undefined) sorted[key] = perm[key];
  }
  // Add any extra keys not in the predefined order
  for (const key of Object.keys(perm)) {
    if (!keyOrder.includes(key)) sorted[key] = perm[key];
  }
  return sorted;
}

// --- Merge permissions ---
console.log('[2/5] Merging permission templates into agent definitions...');

const stats = { orchestrator: 0, readwrite: 0, readonly: 0, sddorchestrator: 0, reviewer: 0, auto: 0, 'auto-sub': 0, semi: 0, total: 0 };

const orderedAgents = {};
for (const [agentName, agentDef] of Object.entries(base.agent)) {
  const templateName = detectTemplate(agentName);
  const template = templates[templateName];

  if (!template) {
    console.error(`ERROR: Template "${templateName}" not found for agent "${agentName}"`);
    process.exit(1);
  }

  // Start with template permission (deep clone)
  const permission = JSON.parse(JSON.stringify(template));

  // Apply agent-specific overrides (hidden, custom perm keys, etc.)
  const agentOverrides = overrides[agentName] || {};
  if (agentOverrides.hidden !== undefined) {
    agentDef.hidden = agentOverrides.hidden;
  }
  if (agentOverrides.extraPermKeys) {
    // Guard against clobbering template permissions
    const templateKeys = Object.keys(template);
    const collisions = templateKeys.filter(k => k in agentOverrides.extraPermKeys);
    if (collisions.length > 0) {
      console.error(`ERROR: extraPermKeys for "${agentName}" collides with template keys: ${collisions.join(', ')}`);
      process.exit(1);
    }
    Object.assign(permission, agentOverrides.extraPermKeys);
  }

  // Sort permission keys to match original ordering
  const sortedPerm = sortPermKeys(permission, agentName);

  // Rebuild agent with correct key order
  // sdd-orchestrator: description, model, mode, permission, prompt (permission BEFORE prompt)
  // SDD agents: description, hidden, mode, prompt, permission
  // Others: description, [model], mode, prompt, permission, [tools]
  const rebuilt = {};
  let keyOrder;
  if (agentName === 'sdd-orchestrator') {
    keyOrder = ['description', 'model', 'mode', 'permission', 'prompt'];
  } else if (agentName === 'gentle-orchestrator') {
    keyOrder = ['description', 'model', 'mode', 'permission', 'prompt', 'tools'];
  } else {
    keyOrder = ['description', 'model', 'hidden', 'mode', 'prompt', 'permission', 'tools'];
  }

  for (const key of keyOrder) {
    if (key === 'permission') {
      rebuilt.permission = sortedPerm;
    } else if (key === 'hidden' && agentDef.hidden !== undefined) {
      rebuilt.hidden = agentDef.hidden;
    } else if (agentDef[key] !== undefined) {
      rebuilt[key] = agentDef[key];
    }
  }

  orderedAgents[agentName] = rebuilt;
  stats[templateName]++;
  stats.total++;
}

base.agent = orderedAgents;

console.log(`  Orchestrator:     ${stats.orchestrator} agent(s)`);
console.log(`  Read/Write:       ${stats.readwrite} agent(s)`);
console.log(`  Read-Only:        ${stats.readonly} agent(s)`);
console.log(`  SDD Orchestrator: ${stats.sddorchestrator} agent(s)`);
console.log(`  Reviewer:         ${stats.reviewer} agent(s)`);
  console.log(`  AUTO variants:    ${stats.auto} agent(s)`);
  console.log(`  AUTO-SUB variants: ${stats['auto-sub']} agent(s)`);
  console.log(`  SEMI variants:    ${stats.semi} agent(s)`);

// --- Serialize ---
console.log('[3/5] Serializing output...');
const output = JSON.stringify(base);

// --- Validate or write ---
if (VALIDATE) {
  console.log('[4/5] Validating against existing opencode.json...');

  let existing = fs.readFileSync(OUTPUT_PATH, 'utf8');
  // Strip BOM if present
  if (existing.charCodeAt(0) === 0xFEFF) existing = existing.slice(1);
  // Normalize line endings
  existing = existing.replace(/\r\n/g, '\n');
  // Ignore trailing newline (end-of-file-fixer may add one)
  existing = existing.replace(/\n$/, '');

  const normalized = output.replace(/\r\n/g, '\n');

  if (existing === normalized) {
    console.log('  VALID — generated output matches existing opencode.json');
    process.exit(0);
  } else {
    console.log('  MISMATCH — generated output differs from existing opencode.json');

    const existingLines = existing.split('\n').length;
    const generatedLines = normalized.split('\n').length;
    console.log(`  Existing:  ${existingLines} lines`);
    console.log(`  Generated: ${generatedLines} lines`);

    // Find ALL differences
    const existingArr = existing.split('\n');
    const generatedArr = normalized.split('\n');
    const diffs = [];
    for (let i = 0; i < Math.max(existingArr.length, generatedArr.length); i++) {
      if (existingArr[i] !== generatedArr[i]) {
        diffs.push({
          line: i + 1,
          existing: existingArr[i] || '(EOF)',
          generated: generatedArr[i] || '(EOF)',
        });
        if (diffs.length >= 10) {
          diffs.push({ line: '...', existing: `(${existingArr.length - i - 1} more)`, generated: '' });
          break;
        }
      }
    }

    for (const d of diffs) {
      console.log(`  Line ${d.line}:`);
      console.log(`    Existing:  ${JSON.stringify(d.existing)}`);
      console.log(`    Generated: ${JSON.stringify(d.generated)}`);
    }

    process.exit(1);
  }
} else {
  console.log(`[4/5] Writing to ${OUTPUT_PATH}...`);

  // Write with BOM to match original file
  const BOM = '\uFEFF';
  fs.writeFileSync(OUTPUT_PATH, BOM + output, 'utf8');

  console.log('[5/5] Verifying output...');
  const written = fs.readFileSync(OUTPUT_PATH, 'utf8').replace(/^\uFEFF/, '');
  if (written === output) {
    const lineCount = output.split('\n').length;
    console.log(`  Written: ${lineCount} lines — verified OK`);
  } else {
    console.error('  ERROR: Written file does not match generated output!');
    process.exit(1);
  }

  console.log('  Done!');
}
