#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - SQLite Functions
# ============================================================================
# SQLite persistence with FTS5 full-text search for review history.
# Provides storage, retrieval, and search capabilities for code reviews.
# ============================================================================

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

    # Sanitize all string inputs
    local project_path project_name git_branch git_commit files diff_content diff_hash result status provider model
    project_path=$(_sql_escape "$1")
    project_name=$(_sql_escape "$2")
    git_branch=$(_sql_escape "$3")
    git_commit=$(_sql_escape "$4")
    files=$(_sql_escape "$5")
    diff_content=$(_sql_escape "$7")
    diff_hash=$(_sql_escape "$8")
    result=$(_sql_escape "$9")
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
