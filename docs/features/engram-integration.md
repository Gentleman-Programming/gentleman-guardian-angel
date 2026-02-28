# Engram Integration

GGA integrates bidirectionally with [Engram](https://github.com/Gentleman-Programming/engram), a persistent memory system for AI coding agents.

## Overview

```
BEFORE review:
  GGA → GET /api/search → Engram → relevant memories → inject into prompt

AFTER review:
  GGA → POST /api/save → Engram → observation stored

gga run → review → save_review_to_db()
                      ├→ _strip_private()       (privacy)
                      ├→ db_save_review()        (local SQLite)
                      ├→ extract_review_insights() (structured insights)
                      └→ engram_save_observation() (→ Engram HTTP)
```

## Setup

1. Install and start Engram:
   ```bash
   brew install gentleman-programming/tap/engram
   engram serve &
   ```

2. Enable the bridge in your `.gga` config:
   ```bash
   GGA_ENGRAM_ENABLED="true"
   ```

3. Run reviews as normal:
   ```bash
   gga run
   ```

## How Context Injection Works

When Engram is enabled, GGA queries Engram **before** each review:

1. Extracts file basenames from the staged files (e.g., `auth.ts`, `user.service.ts`)
2. Searches Engram filtered by project name + file basenames
3. Engram returns up to 5 relevant memories (FTS5 + BM25 ranking)
4. GGA injects them as `=== HISTORICAL CONTEXT ===` in the prompt

This gives the AI reviewer awareness of past decisions, known bugs, and project patterns.

### Token Budget

- Maximum 5 memories injected (~500 tokens)
- Each memory truncated to 200 characters
- Represents ~2-5% of a typical review prompt
- Configurable via `GGA_ENGRAM_CONTEXT_LIMIT`

## Commands

```bash
gga engram check       # Check Engram bridge status
gga engram export 42   # Export review #42 insights to Engram format
gga engram recent 7    # Export insights from last 7 days
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_ENGRAM_ENABLED` | `false` | Enable/disable Engram bridge |
| `GGA_ENGRAM_HOST` | `http://localhost:7437` | Engram HTTP API URL |
| `GGA_ENGRAM_TIMEOUT` | `3` | HTTP timeout in seconds |
| `GGA_ENGRAM_CONTEXT_LIMIT` | `5` | Max memories to inject |
| `GGA_ENGRAM_OUTPUT_DIR` | *(empty)* | Directory for JSON export files |

## Graceful Degradation

The Engram bridge **never** blocks or fails the review pipeline:

- If `GGA_ENGRAM_ENABLED=false` → all bridge functions return immediately
- If Engram server is not running → skip silently, review proceeds normally
- If HTTP timeout is reached → skip silently
- If `curl` is not installed → skip silently
- If `jq` is not installed → use fallback JSON encoding

GGA works exactly the same with or without Engram. The bridge is purely additive.

## Type Mapping

GGA insight types map to Engram observation categories:

| GGA Type | Engram Category | Strength |
|----------|----------------|----------|
| security | observation | 0.8-1.0 |
| bugfix | observation | 0.5-0.8 |
| decision | decision | 0.5-0.8 |
| pattern | pattern | 0.3-0.7 |
| style | insight | 0.3-0.5 |
| performance | observation | 0.5-0.8 |

Severity maps to strength: critical=1.0, high=0.8, medium=0.5, low=0.3
