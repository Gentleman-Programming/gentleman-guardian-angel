# Debug & Inspection Tools

> These commands are for **power users** who want to inspect GGA's internal state, debug issues, or explore the data. **Normal usage doesn't require these tools.**

---

## Overview

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `gga search` | Query review database | Debug retrieval issues |
| `gga predict` | Manual predictions | Test Hebbian memory |
| `gga memory` | Hebbian memory stats | Inspect learned patterns |
| `gga history` | View past reviews | Normal use (also useful) |

---

## gga search

Query the review database directly.

### Usage

```bash
# Basic search
gga search "sql injection"

# Search modes
gga search --mode=lexical "exact keywords"    # FTS5 only
gga search --mode=semantic "conceptual query"  # Embeddings only
gga search --mode=hybrid "balanced search"     # Both (default)

# Adjust hybrid balance
gga search --alpha=0.3 "more semantic"         # 0=semantic, 1=lexical
gga search --alpha=0.7 "more lexical"

# Find similar to specific review
gga search --similar-to 42

# Limit results
gga search --limit 5 "query"
```

### FTS5 Query Syntax

```bash
# AND (implicit)
gga search "sql injection"           # Must contain both

# OR
gga search "sql OR mongodb"          # Either word

# NOT
gga search "sql NOT postgres"        # SQL but not postgres

# Phrase
gga search '"sql injection"'         # Exact phrase

# Prefix
gga search "auth*"                   # auth, authentication...

# Column-specific
gga search "files:login.ts"          # Only in files column
gga search "result:vulnerability"    # Only in result column
```

### Output Format

```
Search Results for: authentication issues
Mode: hybrid | Alpha: 0.5 | Limit: 20

  0.8542 | 42 | FAILED | myapp | >>>authentication<<< token validation...
  0.7823 | 38 | PASSED | myapp | JWT >>>authentication<<< middleware...
  0.6891 | 35 | FAILED | api   | Login >>>issues<<< with session...
```

### When to Use

- RAG not finding relevant context
- Verify reviews are being stored correctly
- Debug similarity scoring
- Explore what's in the database

---

## gga predict

Manually trigger Hebbian predictions.

### Usage

```bash
# Predict from file
gga predict src/auth/login.ts

# Predict from text
gga predict "login jwt token validation"
```

### Output

```
=== PREDICTIONS FOR: src/auth/login.ts ===

Detected concepts:
  - pattern:authentication
  - file:login.ts

Related concepts (by association strength):
  0.89  pattern:security
  0.67  pattern:validation
  0.45  error:null_reference

Potential issues to watch for:
  - security (confidence: 89%)
  - validation (confidence: 67%)
  - null_reference (confidence: 45%)
```

### When to Use

- Test what predictions would be made
- Debug Hebbian learning
- Explore learned associations
- Verify pattern detection

---

## gga memory

Inspect Hebbian memory state.

### Usage

```bash
# Show statistics
gga memory stats

# Initialize tables (usually automatic)
gga memory init

# Show all associations
gga memory show

# Show associations for specific concept
gga memory show "pattern:authentication"

# Apply decay manually
gga memory decay      # 1 day
gga memory decay 7    # 7 days
```

### Stats Output

```
Hebbian Memory Stats:
  Concepts: 47
  Associations: 156
  Average Weight: 0.6234
  Max Weight: 0.9800
  Learning Rate: 0.1
  Decay Rate: 0.99
  Threshold: 0.1

Top associations:
  pattern:authentication <-> pattern:security (0.98)
  pattern:database <-> pattern:validation (0.87)
  file:auth.ts <-> pattern:authentication (0.82)
```

### Show Output

```
Associations for: pattern:authentication
  0.9800  pattern:security
  0.8200  file:auth.ts
  0.7500  pattern:validation
  0.6100  error:null_reference
  0.4500  pattern:api
```

### When to Use

- Debug prediction accuracy
- See what patterns GGA learned
- Identify strong/weak associations
- Manually trigger decay

---

## gga history

View past reviews.

### Usage

```bash
# Last 50 reviews (default)
gga history

# Custom limit
gga history --limit 10

# Filter by status
gga history --status FAILED
gga history --status PASSED

# Filter by project
gga history --project myapp

# Combine filters
gga history --status FAILED --project api --limit 5
```

### Output

```
  ID | Date                | Status | Project    | Files
  42 | 2024-01-15 10:30:00 | PASSED | myapp      | 3 file(s)
  41 | 2024-01-15 09:15:00 | FAILED | myapp      | 1 file(s)
  40 | 2024-01-14 16:45:00 | PASSED | api        | 2 file(s)
```

### When to Use

- See review history (normal use)
- Find specific review ID for `--similar-to`
- Check review frequency
- Audit project coverage

---

## Direct Database Access

For advanced debugging, access SQLite directly:

```bash
# Open database
sqlite3 ~/.gga/gga.db

# Common queries
sqlite3 ~/.gga/gga.db "SELECT COUNT(*) FROM reviews;"
sqlite3 ~/.gga/gga.db "SELECT status, COUNT(*) FROM reviews GROUP BY status;"
sqlite3 ~/.gga/gga.db "SELECT * FROM reviews ORDER BY created_at DESC LIMIT 5;"

# Check embeddings
sqlite3 ~/.gga/gga.db "SELECT COUNT(*) FROM reviews WHERE embedding IS NOT NULL;"

# Check Hebbian tables
sqlite3 ~/.gga/gga.db "SELECT COUNT(*) FROM concepts;"
sqlite3 ~/.gga/gga.db "SELECT COUNT(*) FROM associations;"
sqlite3 ~/.gga/gga.db "SELECT * FROM associations ORDER BY weight DESC LIMIT 10;"
```

---

## Debug Mode

Enable verbose output for any command:

```bash
# Debug RAG
GGA_DEBUG=1 gga run 2>&1 | grep -i rag

# Debug embeddings
GGA_DEBUG=1 gga run 2>&1 | grep -i embed

# Debug Hebbian
GGA_DEBUG=1 gga run 2>&1 | grep -i hebbian

# Full debug output
GGA_DEBUG=1 gga run
```

---

## Troubleshooting Scenarios

### "RAG not finding relevant reviews"

```bash
# 1. Check reviews exist
gga history --limit 5

# 2. Check search works
gga search "your keywords"

# 3. Check embeddings exist
sqlite3 ~/.gga/gga.db "SELECT COUNT(*) FROM reviews WHERE embedding IS NOT NULL;"

# 4. Lower similarity threshold
export GGA_RAG_MIN_SIMILARITY=0.2
gga run
```

### "Predictions seem wrong"

```bash
# 1. Check what concepts are detected
gga predict "your code text"

# 2. See learned associations
gga memory show "pattern:detected"

# 3. Check association count
gga memory stats

# 4. Apply decay if stale
gga memory decay 7
```

### "Database issues"

```bash
# Check database exists
ls -la ~/.gga/gga.db

# Check tables
sqlite3 ~/.gga/gga.db ".tables"

# Rebuild FTS5 index
sqlite3 ~/.gga/gga.db "INSERT INTO reviews_fts(reviews_fts) VALUES('rebuild');"

# Vacuum database
sqlite3 ~/.gga/gga.db "VACUUM;"
```

### "Slow performance"

```bash
# Check database size
du -sh ~/.gga/gga.db

# Reduce context
export GGA_RAG_CONTEXT_LIMIT=3

# Increase similarity threshold (fewer matches)
export GGA_RAG_MIN_SIMILARITY=0.5

# Disable features temporarily
gga run --no-rag
```

---

## Environment Variables Reference

### RAG

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_RAG_ENABLED` | `true` | Enable RAG |
| `GGA_RAG_CONTEXT_LIMIT` | `5` | Max reviews in context |
| `GGA_RAG_MIN_SIMILARITY` | `0.3` | Min similarity threshold |
| `GGA_RAG_MAX_TOKENS` | `2000` | Token budget |
| `GGA_RAG_RECENCY_BOOST` | `0.1` | Recency preference |

### Hebbian

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_HEBBIAN_ENABLED` | `true` | Enable Hebbian |
| `GGA_HEBBIAN_LEARNING_RATE` | `0.1` | Learning speed |
| `GGA_HEBBIAN_DECAY_RATE` | `0.99` | Daily decay |
| `GGA_HEBBIAN_THRESHOLD` | `0.1` | Min weight |

### Search

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_SEARCH_ALPHA` | `0.5` | Hybrid balance |
| `GGA_SEARCH_LIMIT` | `20` | Max results |
| `GGA_SEMANTIC_MIN_SIMILARITY` | `0.3` | Semantic threshold |

### Embeddings

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_EMBED_PROVIDER` | `auto` | Provider or fallback |
| `OLLAMA_HOST` | `localhost:11434` | Ollama endpoint |
| `GOOGLE_API_KEY` | - | Gemini API key |
| `GITHUB_TOKEN` | - | GitHub token |
| `OPENAI_API_KEY` | - | OpenAI API key |

### General

| Variable | Default | Description |
|----------|---------|-------------|
| `GGA_DB_PATH` | `~/.gga/gga.db` | Database path |
| `GGA_DEBUG` | `false` | Enable debug output |
| `GGA_HISTORY_LIMIT` | `50` | Default history limit |
