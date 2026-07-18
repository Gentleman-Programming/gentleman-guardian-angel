# Security Audit Mode

GGA can function as a pre-commit **security auditor** by pointing `RULES_FILE` to a security-focused rules file. No fork or modification needed — GGA is rules-agnostic.

A ready-to-use template based on **OWASP Top 10:2025** is included at `templates/AGENTS-security.md`.

## Quick Start

### Single-mode: security audit only

```bash
cd /path/to/repo
gga init
cp templates/AGENTS-security.md ./AGENTS.md
gga install
```

Every commit now passes through OWASP Top 10:2025 security review.

### Dual-mode: coding standards + security audit

Use `RULES_FILES` (plural) in your `.gga` to run both reviews automatically on every commit:

```bash
# .gga
PROVIDER="ollama:kimi-k2.7-code:cloud"
RULES_FILES="AGENTS.md,AGENTS-security.md"
FILE_PATTERNS="*.ts,*.tsx,*.js,*.jsx,*.py"
EXCLUDE_PATTERNS="*.test.*,*.spec.*,*.d.ts,dist/*,build/*,node_modules/*"
STRICT_MODE="true"
TIMEOUT="300"
```

Behavior:

```
git commit -> gga run -> [AGENTS.md review] -> [AGENTS-security.md review] -> PASS/FAIL
```

Both reviews run automatically. If either fails, the commit is blocked.

### On-demand: env var override

Use `GGA_RULES_FILE` to override the rules file for a single run without editing `.gga`:

```bash
# Coding standards (from .gga)
gga run

# Security audit (env var override)
GGA_RULES_FILE="AGENTS-security.md" gga run --no-cache
```

This is useful for CI pipelines that run different review types on different triggers:

```bash
# .github/workflows/security-review.yml
- name: Security audit on PR
  run: GGA_RULES_FILE="AGENTS-security.md" gga run --pr-mode --no-cache
```

## OWASP Top 10:2025 Categories

The template covers all 10 categories from the latest OWASP release (2025):

| ID | Category | What it catches |
|----|----------|-----------------|
| A01 | Broken Access Control | IDOR, missing auth checks, role escalation, CORS misconfiguration |
| A02 | Security Misconfiguration | Debug in prod, default credentials, missing security headers |
| A03 | Software Supply Chain Failures | Vulnerable dependencies, unsigned CI/CD, unpinned Docker images |
| A04 | Cryptographic Failures | MD5/SHA-1, hardcoded secrets, weak random, HTTP for sensitive data |
| A05 | Injection | SQLi, NoSQLi, command injection, template injection, log injection |
| A06 | Insecure Design | No rate limiting, missing CSRF, predictable IDs, no file validation |
| A07 | Authentication Failures | Session fixation, non-rotating tokens, weak password policy |
| A08 | Software or Data Integrity Failures | Unsafe deserialization, unsigned commits, CI secret exposure |
| A09 | Security Logging and Alerting Failures | No auth logging, sensitive data in logs, no alerting |
| A10 | Mishandling of Exceptional Conditions | Empty catch blocks, inconsistent state, resource leaks |

### Key changes from OWASP 2021

| 2021 | 2025 | Change |
|------|------|--------|
| A02: Cryptographic Failures | A04 | Moved down |
| A03: Injection | A05 | Moved down |
| A05: Security Misconfiguration | A02 | Moved up |
| A06: Vulnerable Components | A03: Supply Chain Failures | Renamed, expanded |
| A10: SSRF | A10: Mishandling Exceptional Conditions | Replaced |

## Provider Recommendations for Security Review

Security review benefits from models with strong reasoning on code:

| Model | Config Value | Strengths |
|-------|-------------|-----------|
| Kimi k2.7 Code | `ollama:kimi-k2.7-code:cloud` | Best coverage - detects more findings (rate limiting, insecure design). 262K context. |
| GLM-5.2 | `ollama:glm-5.2:cloud` | Better severity classification. 1M context. Slower. |
| DeepSeek V4 Pro | `ollama:deepseek-v4-pro:cloud` | Fastest. Clean, concise output. Good for quick feedback loops. |

## Response Format

The security audit template requires structured output:

```
STATUS: FAILED
file:line - [A0X] Category - issue description - severity (CRITICAL/HIGH/MEDIUM/LOW)
```

This format is machine-parseable and works well with the grounded verification proposed in #106.

## Cache Behavior

When using `RULES_FILES` (plural), each rules file gets its own cache namespace. Cache from coding standards review does not contaminate cache from security audit, and vice versa. This means:

- Changing `AGENTS.md` invalidates only coding standards cache
- Changing `AGENTS-security.md` invalidates only security audit cache
- Unchanged files skip re-review per rules file independently
