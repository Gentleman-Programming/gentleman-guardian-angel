# Review Persistence (SQLite + FTS5)

GGA stores every code review result in a local SQLite database with full-text
search powered by FTS5. This gives you a searchable history of all reviews
across every project on your machine.

## Quick start

```bash
# Run a review — results are saved automatically
gga run

# Browse recent reviews
gga history

# Search past reviews
gga search "authentication"
```

No extra configuration is needed. If `sqlite3` is available on your system, GGA
saves reviews automatically after each run. If `sqlite3` is not installed, GGA
continues working normally — persistence is fully opt-in via graceful
degradation.

## Commands

### `gga history`

Shows recent review results sorted by date (newest first).

```bash
gga history                         # last 50 reviews (default)
gga history --limit 10              # last 10 reviews
gga history --status FAILED         # only failed reviews
gga history --project my-app        # filter by project name
gga history --status PASSED --limit 5
```

| Flag | Description | Default |
|------|-------------|---------|
| `--limit N` | Number of reviews to show | `50` (or `GGA_HISTORY_LIMIT`) |
| `--status S` | Filter by status: `PASSED`, `FAILED`, `ERROR`, `UNKNOWN` | all |
| `--project P` | Filter by project name | all |

### `gga search <query>`

Full-text search across review results, file names, and diff content using
SQLite FTS5. Results are ranked by relevance (BM25).

```bash
gga search "sql injection"          # find reviews mentioning SQL injection
gga search "*.tsx" --limit 5        # find reviews involving TSX files
gga search "security vulnerability"
```

| Flag | Description | Default |
|------|-------------|---------|
| `--limit N` | Max results to return | `20` (or `GGA_SEARCH_LIMIT`) |

## Configuration

All settings are optional — sensible defaults are built in.

| Variable | Description | Default |
|----------|-------------|---------|
| `GGA_DB_PATH` | Path to the SQLite database file | `~/.gga/gga.db` |
| `GGA_HISTORY_LIMIT` | Default limit for `gga history` | `50` |
| `GGA_SEARCH_LIMIT` | Default limit for `gga search` | `20` |

Set these as environment variables or in your shell profile:

```bash
export GGA_DB_PATH="$HOME/.gga/reviews.db"
export GGA_HISTORY_LIMIT="100"
```

## Architecture

### Database schema

GGA uses a single `reviews` table with an FTS5 virtual table for search:

```
reviews
├── id              INTEGER PRIMARY KEY
├── created_at      TEXT (datetime)
├── project_path    TEXT
├── project_name    TEXT
├── git_branch      TEXT
├── git_commit      TEXT
├── files           TEXT (comma-separated)
├── files_count     INTEGER
├── diff_content    TEXT
├── diff_hash       TEXT NOT NULL UNIQUE
├── result          TEXT (AI review output)
├── status          TEXT (PASSED|FAILED|ERROR|UNKNOWN)
├── provider        TEXT
├── model           TEXT
└── duration_ms     INTEGER

reviews_fts (FTS5 virtual table)
├── files
├── result
└── diff_content
```

FTS5 is kept in sync via `AFTER INSERT/UPDATE/DELETE` triggers — no manual
reindexing needed.

### Deduplication

Reviews are deduplicated by `diff_hash` (SHA-256 of the diff content). If
you run the same review twice on unchanged code, GGA updates the existing
record via `ON CONFLICT(diff_hash) DO UPDATE` instead of creating duplicates.

### Security

- All SQL parameters are sanitized via `_sql_escape()` (doubles single quotes)
- Integer parameters are validated via `_sql_validate_int()`
- FTS5 queries are sanitized via `_fts5_sanitize()` (prevents operator injection)
- `GGA_DB_PATH` is validated against shell metacharacter injection

### Graceful degradation

If `sqlite3` is not installed:

- `gga run` works normally (just doesn't save results)
- `gga history` and `gga search` show a clear error message
- No crashes, no broken pipelines

## Maintenance

GGA includes built-in maintenance functions (available programmatically):

- **Cleanup**: keeps the last N reviews per project, vacuums the database
- **Integrity check**: runs `PRAGMA integrity_check` on the database

The database is lightweight — thousands of reviews typically use < 10 MB.
