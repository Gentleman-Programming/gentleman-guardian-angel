#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - SQLite Functions
# ============================================================================
# SQLite persistence with FTS5 full-text search for review history.
# Provides storage, retrieval, and search capabilities for code reviews.
# ============================================================================

# ============================================================================
# Privacy Helpers
# ============================================================================

# Strip sensitive data from text before storage
# Two layers: explicit <private> tags + common secret patterns
# Usage: _strip_private "text with secrets"
# Returns: text with secrets replaced by [REDACTED]
_strip_private() {
    local text="$1"
    [[ -z "$text" ]] && return 0

    printf '%s' "$text" | sed -E \
        -e 's/<private>[^<]*<\/private>/[REDACTED]/g' \
        -e 's/(sk-|sk_live_|sk_test_)[a-zA-Z0-9_-]{10,}/[REDACTED]/g' \
        -e 's/(ghp_|gho_|ghu_|ghs_|ghr_)[a-zA-Z0-9]{10,}/[REDACTED]/g' \
        -e 's/AIza[a-zA-Z0-9_-]{30,}/[REDACTED]/g' \
        -e 's/(Bearer|token) [a-zA-Z0-9._-]{20,}/\1 [REDACTED]/gi' \
        -e 's/(password|secret|api_key|apikey|api_secret|access_token|private_key)=[^ "'\'']+/\1=[REDACTED]/gi' \
        -e 's/-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----[^-]*-----END (RSA |EC |OPENSSH )?PRIVATE KEY-----/[REDACTED_KEY]/g'
}

# ============================================================================
# SQL Security Helpers
# ============================================================================

# Escape string for safe SQL interpolation
# Handles single quotes and other potentially dangerous characters
_sql_escape() {
    local str="$1"
    # Escape single quotes by doubling them (SQL standard)
    str="${str//\'/\'\'}"
    # Remove null bytes which can cause issues
    str="${str//$'\0'/}"
    printf '%s' "$str"
}

# Validate that a value is a positive integer
_sql_validate_int() {
    local val="$1"
    local default="${2:-0}"
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        printf '%s' "$val"
    else
        printf '%s' "$default"
    fi
}

# Validate status is one of allowed values
_sql_validate_status() {
    local status="$1"
    case "$status" in
        PASSED|FAILED|ERROR|UNKNOWN) printf '%s' "$status" ;;
        *) printf '%s' "UNKNOWN" ;;
    esac
}

# ============================================================================
# Database Initialization
# ============================================================================

# Initialize database with schema
db_init() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Ensure directory exists
    mkdir -p "$(dirname "$db_path")"

    # Create tables and indexes
    sqlite3 "$db_path" <<'SQL'
-- Main reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    project_path TEXT NOT NULL,
    project_name TEXT NOT NULL,
    git_branch TEXT,
    git_commit TEXT,
    files TEXT NOT NULL,
    files_count INTEGER NOT NULL,
    diff_content TEXT,
    diff_hash TEXT,
    result TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('PASSED', 'FAILED', 'ERROR', 'UNKNOWN')),
    provider TEXT NOT NULL,
    model TEXT,
    duration_ms INTEGER,
    embedding BLOB,
    UNIQUE(diff_hash)
);

-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS reviews_fts USING fts5(
    files, result, diff_content,
    content='reviews', content_rowid='id'
);

-- Triggers to keep FTS5 in sync with reviews table
CREATE TRIGGER IF NOT EXISTS reviews_ai AFTER INSERT ON reviews BEGIN
    INSERT INTO reviews_fts(rowid, files, result, diff_content)
    VALUES (new.id, new.files, new.result, new.diff_content);
END;

CREATE TRIGGER IF NOT EXISTS reviews_ad AFTER DELETE ON reviews BEGIN
    INSERT INTO reviews_fts(reviews_fts, rowid, files, result, diff_content)
    VALUES ('delete', old.id, old.files, old.result, old.diff_content);
END;

CREATE TRIGGER IF NOT EXISTS reviews_au AFTER UPDATE ON reviews BEGIN
    INSERT INTO reviews_fts(reviews_fts, rowid, files, result, diff_content)
    VALUES ('delete', old.id, old.files, old.result, old.diff_content);
    INSERT INTO reviews_fts(rowid, files, result, diff_content)
    VALUES (new.id, new.files, new.result, new.diff_content);
END;

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_reviews_project ON reviews(project_name);
CREATE INDEX IF NOT EXISTS idx_reviews_status ON reviews(status);
CREATE INDEX IF NOT EXISTS idx_reviews_created ON reviews(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_diff_hash ON reviews(diff_hash);

-- Structured insights extracted from reviews
CREATE TABLE IF NOT EXISTS review_insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK(type IN (
        'bugfix','security','pattern','decision','style','performance'
    )),
    what TEXT NOT NULL,
    why TEXT,
    file_path TEXT,
    learned TEXT,
    severity TEXT DEFAULT 'medium' CHECK(severity IN ('low','medium','high','critical')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_insights_type ON review_insights(type);
CREATE INDEX IF NOT EXISTS idx_insights_review ON review_insights(review_id);
CREATE INDEX IF NOT EXISTS idx_insights_severity ON review_insights(severity);

-- FTS5 for insight search
CREATE VIRTUAL TABLE IF NOT EXISTS insights_fts USING fts5(
    what, why, learned, file_path, type,
    content='review_insights', content_rowid='id'
);

CREATE TRIGGER IF NOT EXISTS insights_ai AFTER INSERT ON review_insights BEGIN
    INSERT INTO insights_fts(rowid, what, why, learned, file_path, type)
    VALUES (new.id, new.what, new.why, new.learned, new.file_path, new.type);
END;

CREATE TRIGGER IF NOT EXISTS insights_ad AFTER DELETE ON review_insights BEGIN
    INSERT INTO insights_fts(insights_fts, rowid, what, why, learned, file_path, type)
    VALUES ('delete', old.id, old.what, old.why, old.learned, old.file_path, old.type);
END;
SQL

    echo "$db_path"
}

# ============================================================================
# CRUD Operations
# ============================================================================

# Save a review to the database
# Usage: db_save_review "project_path" "project_name" "branch" "commit" "files" count "diff" "diff_hash" "result" "status" "provider" "model" duration_ms
db_save_review() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Strip sensitive data before storage (Layer 2: store-level)
    local clean_diff clean_result
    clean_diff=$(_strip_private "$7")
    clean_result=$(_strip_private "$9")

    # Sanitize all string inputs
    local project_path project_name git_branch git_commit files diff_content diff_hash result status provider model
    project_path=$(_sql_escape "$1")
    project_name=$(_sql_escape "$2")
    git_branch=$(_sql_escape "$3")
    git_commit=$(_sql_escape "$4")
    files=$(_sql_escape "$5")
    diff_content=$(_sql_escape "$clean_diff")
    diff_hash=$(_sql_escape "$8")
    result=$(_sql_escape "$clean_result")
    provider=$(_sql_escape "${11}")
    model=$(_sql_escape "${12:-}")

    # Validate numeric and enum inputs
    local files_count duration_ms
    files_count=$(_sql_validate_int "$6" 0)
    duration_ms=$(_sql_validate_int "${13}" 0)
    status=$(_sql_validate_status "${10}")

    sqlite3 "$db_path" <<SQL
INSERT OR REPLACE INTO reviews (
    project_path, project_name, git_branch, git_commit,
    files, files_count, diff_content, diff_hash,
    result, status, provider, model, duration_ms
) VALUES (
    '$project_path', '$project_name', '$git_branch', '$git_commit',
    '$files', $files_count, '$diff_content', '$diff_hash',
    '$result', '$status', '$provider', '$model', $duration_ms
);
SQL
}

# Get reviews with optional filters
# Usage: db_get_reviews [limit] [status] [project]
db_get_reviews() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local limit status_filter project_filter

    limit=$(_sql_validate_int "${1:-50}" 50)

    local where_clause=""
    if [[ -n "$2" ]]; then
        status_filter=$(_sql_validate_status "$2")
        where_clause="WHERE status = '$status_filter'"
    fi
    if [[ -n "$3" ]]; then
        project_filter=$(_sql_escape "$3")
        if [[ -n "$where_clause" ]]; then
            where_clause="$where_clause AND project_name = '$project_filter'"
        else
            where_clause="WHERE project_name = '$project_filter'"
        fi
    fi

    sqlite3 -json "$db_path" <<SQL
SELECT id, created_at, status, files_count, project_name, provider,
       substr(result, 1, 200) as summary
FROM reviews
$where_clause
ORDER BY created_at DESC
LIMIT $limit;
SQL
}

# Get a single review by ID
db_get_review() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id

    review_id=$(_sql_validate_int "$1" 0)
    [[ "$review_id" -eq 0 ]] && return 1

    sqlite3 -json "$db_path" <<SQL
SELECT * FROM reviews WHERE id = $review_id;
SQL
}

# ============================================================================
# Search Operations
# ============================================================================

# Full-text search using FTS5
# Usage: db_search_reviews "query" [limit]
db_search_reviews() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local query limit

    # Escape for SQL and sanitize FTS5 special chars
    query=$(_sql_escape "$1")
    # Escape FTS5 operators that could cause issues (basic protection)
    query="${query//\"/\\\"}"
    limit=$(_sql_validate_int "${2:-20}" 20)

    local result
    result=$(sqlite3 -json "$db_path" <<SQL
SELECT
    r.id,
    r.created_at,
    r.status,
    r.project_name,
    r.files_count,
    snippet(reviews_fts, 1, '>>>', '<<<', '...', 32) as match_snippet,
    rank
FROM reviews_fts
JOIN reviews r ON reviews_fts.rowid = r.id
WHERE reviews_fts MATCH '$query'
ORDER BY rank
LIMIT $limit;
SQL
)
    # Return empty array if no results
    echo "${result:-[]}"
}

# Search by status
db_search_by_status() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local status limit

    status=$(_sql_validate_status "$1")
    limit=$(_sql_validate_int "${2:-20}" 20)

    sqlite3 -json "$db_path" <<SQL
SELECT id, created_at, project_name, files_count,
       substr(result, 1, 200) as summary
FROM reviews
WHERE status = '$status'
ORDER BY created_at DESC
LIMIT $limit;
SQL
}

# ============================================================================
# Review Insights
# ============================================================================

# Save a structured insight extracted from a review
# Usage: db_save_insight review_id type what [why] [file_path] [learned] [severity]
db_save_insight() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id type what why file_path learned severity

    review_id=$(_sql_validate_int "$1" 0)
    type=$(_sql_escape "$2")
    what=$(_sql_escape "$3")
    why=$(_sql_escape "${4:-}")
    file_path=$(_sql_escape "${5:-}")
    learned=$(_sql_escape "${6:-}")
    severity="${7:-medium}"

    # Validate type
    case "$type" in
        bugfix|security|pattern|decision|style|performance) ;;
        *) type="pattern" ;;
    esac

    # Validate severity
    case "$severity" in
        low|medium|high|critical) ;;
        *) severity="medium" ;;
    esac

    sqlite3 "$db_path" <<SQL
INSERT INTO review_insights (review_id, type, what, why, file_path, learned, severity)
VALUES ($review_id, '$type', '$what', '$why', '$file_path', '$learned', '$severity');
SQL
}

# Get insights for a specific review
# Usage: db_get_insights review_id
db_get_insights() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id
    review_id=$(_sql_validate_int "$1" 0)

    sqlite3 -json "$db_path" <<SQL
SELECT id, type, what, why, file_path, learned, severity
FROM review_insights
WHERE review_id = $review_id
ORDER BY severity DESC, id ASC;
SQL
}

# Search insights across all reviews
# Usage: db_search_insights query [limit]
db_search_insights() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local query limit
    query=$(_sql_escape "$1")
    limit=$(_sql_validate_int "${2:-20}" 20)

    sqlite3 -json "$db_path" <<SQL
SELECT
    ri.id,
    ri.review_id,
    ri.type,
    ri.what,
    ri.file_path,
    ri.severity,
    r.project_name,
    r.created_at
FROM insights_fts
JOIN review_insights ri ON insights_fts.rowid = ri.id
JOIN reviews r ON ri.review_id = r.id
WHERE insights_fts MATCH '$query'
ORDER BY rank
LIMIT $limit;
SQL
}

# Get compact insight summaries for RAG context building
# Usage: db_get_insight_summaries review_ids_csv [limit]
db_get_insight_summaries() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_ids="$1"
    local limit
    limit=$(_sql_validate_int "${2:-20}" 20)

    [[ -z "$review_ids" ]] && return 0

    sqlite3 -separator '|' "$db_path" <<SQL
SELECT
    ri.review_id,
    ri.type,
    ri.severity,
    ri.file_path,
    ri.what
FROM review_insights ri
WHERE ri.review_id IN ($review_ids)
ORDER BY
    CASE ri.severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
    END,
    ri.review_id DESC
LIMIT $limit;
SQL
}

# ============================================================================
# Insight Extraction
# ============================================================================

# Extract structured insights from an AI review result
# Parses the review text looking for issues, warnings, and recommendations
# Usage: extract_review_insights "result_text" review_id
extract_review_insights() {
    local result="$1"
    local review_id="$2"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$result" || -z "$review_id" ]] && return 0
    [[ ! -f "$db_path" ]] && return 0

    local lower_result
    lower_result=$(printf '%s' "$result" | tr '[:upper:]' '[:lower:]')

    # Detect issue type from content
    local type="pattern"
    if printf '%s' "$lower_result" | grep -qE '(injection|xss|csrf|sanitize|vulnerab|insecure|exploit)'; then
        type="security"
    elif printf '%s' "$lower_result" | grep -qE '(bug|fix|error|crash|null|undefined|exception)'; then
        type="bugfix"
    elif printf '%s' "$lower_result" | grep -qE '(slow|perf|optim|memory|cache|latency|bottleneck)'; then
        type="performance"
    elif printf '%s' "$lower_result" | grep -qE '(style|format|naming|convention|indent|whitespace)'; then
        type="style"
    fi

    # Detect severity
    local severity="medium"
    if printf '%s' "$lower_result" | grep -qE '(critical|severe|urgent|dangerous|vulnerability)'; then
        severity="critical"
    elif printf '%s' "$lower_result" | grep -qE '(warning|should|consider|recommend)'; then
        severity="medium"
    elif printf '%s' "$lower_result" | grep -qE '(minor|trivial|nit|cosmetic)'; then
        severity="low"
    fi

    # Extract file paths mentioned in review
    local file_paths
    file_paths=$(printf '%s' "$result" | grep -oE '[a-zA-Z0-9_/-]+\.(ts|js|tsx|jsx|py|go|rs|sh|java|rb|php)(:[0-9]+)?' | head -5 | tr '\n' ', ' | sed 's/,$//')

    # Extract the main finding as "what" (first substantive line after STATUS)
    local what
    what=$(printf '%s' "$result" | grep -v '^STATUS:' | grep -v '^$' | head -3 | tr '\n' ' ' | sed 's/  */ /g')
    # Truncate to 200 chars
    [[ ${#what} -gt 200 ]] && what="${what:0:200}..."

    [[ -z "$what" ]] && return 0

    db_save_insight "$review_id" "$type" "$what" "" "$file_paths" "" "$severity"
}

# ============================================================================
# Statistics
# ============================================================================

# Get review statistics
db_stats() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    sqlite3 "$db_path" <<'SQL'
SELECT
    COUNT(*) as total_reviews,
    SUM(CASE WHEN status = 'PASSED' THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END) as errors,
    COUNT(DISTINCT project_name) as projects,
    AVG(duration_ms) as avg_duration_ms
FROM reviews;
SQL
}

# Get reviews per project
db_stats_by_project() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    sqlite3 -json "$db_path" <<'SQL'
SELECT
    project_name,
    COUNT(*) as review_count,
    SUM(CASE WHEN status = 'PASSED' THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
    MAX(created_at) as last_review
FROM reviews
GROUP BY project_name
ORDER BY review_count DESC;
SQL
}

# ============================================================================
# Maintenance
# ============================================================================

# Delete old reviews (keep last N per project)
db_cleanup() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local keep

    keep=$(_sql_validate_int "${1:-100}" 100)

    sqlite3 "$db_path" <<SQL
DELETE FROM reviews
WHERE id NOT IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (
            PARTITION BY project_name
            ORDER BY created_at DESC
        ) as rn
        FROM reviews
    )
    WHERE rn <= $keep
);
SQL

    # Vacuum to reclaim space
    sqlite3 "$db_path" "VACUUM;"
}

# Check database integrity
db_check() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    sqlite3 "$db_path" "PRAGMA integrity_check;"
}
