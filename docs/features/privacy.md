# Privacy Stripping

GGA strips sensitive data from review content **before** it reaches the database. This ensures no API keys, tokens, or private keys are persisted in review history.

## Two-Layer Approach

### Layer 1: Explicit Tags

Wrap sensitive content in `<private>` tags and GGA will redact it:

```
Set up API with <private>sk-abc123</private> key
→ Set up API with [REDACTED] key
```

### Layer 2: Automatic Pattern Detection

GGA automatically detects and redacts common secret patterns:

| Pattern | Example | Redacted |
|---------|---------|----------|
| OpenAI keys | `sk-proj-abc123...` | `[REDACTED]` |
| GitHub tokens | `ghp_abc123...` | `[REDACTED]` |
| Google API keys | `AIzaSy...` | `[REDACTED]` |
| Bearer tokens | `Bearer eyJhb...` | `Bearer [REDACTED]` |
| Key=value secrets | `password=secret` | `password=[REDACTED]` |
| PEM private keys | `-----BEGIN PRIVATE KEY-----` | `[REDACTED_KEY]` |

### PEM Key Handling

Multi-line PEM blocks are detected using a stateful `awk` filter that tracks `BEGIN/END PRIVATE KEY` boundaries. This correctly handles:
- RSA private keys
- EC private keys
- OPENSSH private keys

## Over-Redaction Protection

GGA avoids false positives:
- Short strings after prefixes (e.g., `sk-short`) are NOT redacted
- Mentions of "password" in comments without `=` are preserved
- Code structure around redacted values is maintained

## Where It's Applied

Privacy stripping runs in `db_save_review()` on two fields:
- `diff_content` — the git diff being reviewed
- `result` — the AI provider's review output

Other fields (project path, branch, commit hash) are structural metadata and are not stripped.

## Portability

The implementation uses:
- **POSIX-compatible `sed`** with character classes (no GNU-only `gi` flag)
- **`awk`** for multi-line PEM detection (piped after `sed`)

Works on macOS (BSD sed), Linux (GNU sed), and all POSIX systems.

## No Configuration Required

Privacy stripping is always enabled. There is no opt-out — sensitive data should never be persisted.
