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

# Strip sensitive data from text before storage.
# Two layers: explicit <private> tags + common secret patterns.
# Uses portable sed (no GNU-only flags) + awk for multi-line PEM.
# Usage: cleaned=$(_strip_private "text with secrets")
_strip_private() {
    local text="$1"
    [[ -z "$text" ]] && return 0

    printf '%s' "$text" | sed -E \
        -e 's/<private>[^<]*<\/private>/[REDACTED]/g' \
        -e 's/(sk-|sk_live_|sk_test_)[a-zA-Z0-9_-]{10,}/[REDACTED]/g' \
        -e 's/(ghp_|gho_|ghu_|ghs_|ghr_)[a-zA-Z0-9]{10,}/[REDACTED]/g' \
        -e 's/AIza[a-zA-Z0-9_-]{30,}/[REDACTED]/g' \
        -e 's/([Bb][Ee][Aa][Rr][Ee][Rr]|[Tt][Oo][Kk][Ee][Nn]) [a-zA-Z0-9._-]{20,}/\1 [REDACTED]/g' \
        -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii]_[Kk][Ee][Yy]|[Aa][Pp][Ii][Kk][Ee][Yy]|[Aa][Pp][Ii]_[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Cc][Cc][Ee][Ss][Ss]_[Tt][Oo][Kk][Ee][Nn]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]_[Kk][Ee][Yy])=[^ "'\'']+/\1=[REDACTED]/g' \
    | awk '
        BEGIN { in_key = 0 }
        /-----BEGIN .*PRIVATE KEY-----/ { print "[REDACTED_KEY]"; in_key = 1; next }
        in_key && /-----END .*PRIVATE KEY-----/ { in_key = 0; next }
        in_key { next }
        { print }
    '
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
    if ! sqlite3 "$db_path" <<'SQL'
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
    diff_hash TEXT NOT NULL,
    result TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('PASSED', 'FAILED', 'ERROR', 'UNKNOWN')),
    provider TEXT NOT NULL,
    model TEXT,
    duration_ms INTEGER,
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
-- diff_hash already has a UNIQUE constraint which auto-creates an index

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

CREATE TRIGGER IF NOT EXISTS insights_au AFTER UPDATE ON review_insights BEGIN
    INSERT INTO insights_fts(insights_fts, rowid, what, why, learned, file_path, type)
    VALUES ('delete', old.id, old.what, old.why, old.learned, old.file_path, old.type);
    INSERT INTO insights_fts(rowid, what, why, learned, file_path, type)
    VALUES (new.id, new.what, new.why, new.learned, new.file_path, new.type);
END;
SQL
    then
        echo "Error: failed to initialize database at $db_path" >&2
        return 1
    fi

    echo "$db_path"
}

# ============================================================================
# SQL Sanitization Helpers
# ============================================================================

# Escape a string for safe use in SQL single-quoted literals.
# Doubles single quotes: O'Brien → O''Brien
# Usage: local safe_val; safe_val=$(_sql_escape "$raw_value")
_sql_escape() {
    printf '%s' "${1//\'/\'\'}"
}

# Validate that a value is a positive integer (for LIMIT, ID, COUNT, etc.).
# Always succeeds (returns 0). Outputs the value if valid, or the default.
# Usage: limit=$(_sql_validate_int "$user_input" 50)
_sql_validate_int() {
    local value="$1"
    local default="${2:-0}"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$default"
    fi
}

# Sanitize a string for FTS5 MATCH queries.
# Wraps each whitespace-separated token in double quotes to prevent
# FTS5 operator injection (AND, OR, NOT, NEAR, etc.).
# Also strips single quotes to prevent SQL literal breakout.
# Usage: local safe_q; safe_q=$(_fts5_sanitize "$raw_query")
_fts5_sanitize() {
    local query="$1"
    local sanitized=""

    # Remove characters that are special in FTS5: " ( ) * ^
    # Also remove single quotes to prevent SQL injection when
    # the result is embedded in a SQL string literal
    query="${query//\"/}"
    query="${query//\(/}"
    query="${query//\)/}"
    query="${query//\*/}"
    query="${query//^/}"
    query="${query//\'/}"

    # Disable pathname expansion to prevent glob chars (?, [, ])
    # from expanding to filenames during word splitting
    local old_opts; old_opts=$(set +o); set -f

    # Wrap each token in double quotes
    local token
    for token in $query; do
        [[ -z "$token" ]] && continue
        if [[ -n "$sanitized" ]]; then
            sanitized="$sanitized \"$token\""
        else
            sanitized="\"$token\""
        fi
    done

    # Restore original shell options
    eval "$old_opts"

    printf '%s' "$sanitized"
}

# Escape a string for safe inclusion as a JSON string value.
# Handles backslashes, double quotes, and control characters.
# Usage: local safe; safe=$(_json_escape "$raw_value")
_json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//$'\b'/\\b}
    s=${s//$'\f'/\\f}
    printf '%s' "$s"
}

# Normalize json_group_array output: SQLite returns '[null]' instead of '[]'
# when no rows match a query. This helper fixes that.
# Usage: local result; result=$(_json_array_fix "$(sqlite3 ...)")
_json_array_fix() {
    local output="$1"
    if [[ "$output" == '[null]' ]] || [[ -z "$output" ]]; then
        echo "[]"
    else
        echo "$output"
    fi
}

# ============================================================================
# CRUD Operations
# ============================================================================

# Save a review to the database
# Usage: db_save_review "project_path" "project_name" "branch" "commit" "files" count "diff" "diff_hash" "result" "status" "provider" "model" duration_ms
db_save_review() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Strip sensitive data before storage (two-layer privacy)
    local clean_diff; clean_diff=$(_strip_private "$7")
    local clean_result; clean_result=$(_strip_private "$9")

    local project_path; project_path=$(_sql_escape "$1")
    local project_name; project_name=$(_sql_escape "$2")
    local git_branch; git_branch=$(_sql_escape "$3")
    local git_commit; git_commit=$(_sql_escape "$4")
    local files; files=$(_sql_escape "$5")
    local files_count; files_count=$(_sql_validate_int "$6" 0)
    local diff_content; diff_content=$(_sql_escape "$clean_diff")
    local diff_hash; diff_hash=$(_sql_escape "$8")
    local result; result=$(_sql_escape "$clean_result")
    local status; status=$(_sql_escape "${10}")
    local provider; provider=$(_sql_escape "${11}")
    local model; model=$(_sql_escape "${12:-}")
    local duration_ms; duration_ms=$(_sql_validate_int "${13:-0}" 0)

    local sql="INSERT INTO reviews (
    project_path, project_name, git_branch, git_commit,
    files, files_count, diff_content, diff_hash,
    result, status, provider, model, duration_ms
) VALUES (
    '$project_path', '$project_name', '$git_branch', '$git_commit',
    '$files', $files_count, '$diff_content', '$diff_hash',
    '$result', '$status', '$provider', '$model', $duration_ms
)
ON CONFLICT(diff_hash) DO UPDATE SET
    project_path = excluded.project_path,
    project_name = excluded.project_name,
    git_branch = excluded.git_branch,
    git_commit = excluded.git_commit,
    files = excluded.files,
    files_count = excluded.files_count,
    diff_content = excluded.diff_content,
    result = excluded.result,
    status = excluded.status,
    provider = excluded.provider,
    model = excluded.model,
    duration_ms = excluded.duration_ms;"
    if ! sqlite3 "$db_path" <<< "$sql"; then
        echo "Error: failed to save review to database" >&2
        return 1
    fi
}

# Get reviews with optional filters
# Usage: db_get_reviews [limit] [status] [project]
db_get_reviews() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local limit; limit=$(_sql_validate_int "${1:-50}" 50)
    local status_filter; status_filter=$(_sql_escape "${2:-}")
    local project_filter; project_filter=$(_sql_escape "${3:-}")

    local where_clause=""
    if [[ -n "$status_filter" ]]; then
        where_clause="WHERE status = '$status_filter'"
    fi
    if [[ -n "$project_filter" ]]; then
        if [[ -n "$where_clause" ]]; then
            where_clause="$where_clause AND project_name = '$project_filter'"
        else
            where_clause="WHERE project_name = '$project_filter'"
        fi
    fi

    local sql="SELECT json_group_array(json_object(
    'id', id,
    'created_at', created_at,
    'status', status,
    'files_count', files_count,
    'project_name', project_name,
    'provider', provider,
    'summary', substr(result, 1, 200)
))
FROM (
    SELECT id, created_at, status, files_count, project_name, provider, result
    FROM reviews
    $where_clause
    ORDER BY created_at DESC
    LIMIT $limit
);"
    local result
    if ! result=$(sqlite3 "$db_path" <<< "$sql"); then
        _json_array_fix ""
        return 1
    fi
    _json_array_fix "$result"
}
db_get_review() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id; review_id=$(_sql_validate_int "$1" 0)

    local sql="SELECT json_group_array(json_object(
    'id', id,
    'created_at', created_at,
    'project_path', project_path,
    'project_name', project_name,
    'git_branch', git_branch,
    'git_commit', git_commit,
    'files', files,
    'files_count', files_count,
    'diff_content', diff_content,
    'diff_hash', diff_hash,
    'result', result,
    'status', status,
    'provider', provider,
    'model', model,
    'duration_ms', duration_ms
))
FROM reviews WHERE id = $review_id;"
    local result
    if ! result=$(sqlite3 "$db_path" <<< "$sql"); then
        _json_array_fix ""
        return 1
    fi
    _json_array_fix "$result"
}

# ============================================================================
# Search Operations
# ============================================================================

# Full-text search using FTS5
# Usage: db_search_reviews "query" [limit]
db_search_reviews() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local query; query=$(_fts5_sanitize "$1")
    local limit; limit=$(_sql_validate_int "${2:-20}" 20)

    # Empty query after sanitization means no results
    if [[ -z "$query" ]]; then
        echo "[]"
        return 0
    fi

    # FTS5 auxiliary functions (snippet, bm25) cannot be used inside
    # aggregate functions like json_group_array(). Use unit separator (0x1F)
    # for field delimiting — safer than printable chars that may appear in text.
    local sep=$'\x1f'
    local rows
    if ! rows=$(sqlite3 -separator "$sep" "$db_path" <<< "SELECT
    r.id,
    r.created_at,
    r.status,
    r.project_name,
    r.files_count,
    replace(snippet(reviews_fts, 1, '>>>', '<<<', '...', 32), char(31), ''),  -- col 1 = result
    bm25(reviews_fts)
FROM reviews_fts
JOIN reviews r ON reviews_fts.rowid = r.id
WHERE reviews_fts MATCH '$query'
ORDER BY bm25(reviews_fts)
LIMIT $limit;"
    ); then
        echo "Error: FTS5 search query failed" >&2
        echo "[]"
        return 1
    fi

    # Build JSON array from rows
    if [[ -z "$rows" ]]; then
        echo "[]"
        return 0
    fi

    local json="["
    local first=true
    while IFS="$sep" read -r id created_at status project_name files_count match_snippet rank; do
        [[ -z "$id" ]] && continue

        # JSON-escape all string fields
        created_at=$(_json_escape "$created_at")
        status=$(_json_escape "$status")
        project_name=$(_json_escape "$project_name")
        match_snippet=$(_json_escape "$match_snippet")

        if [[ "$first" == true ]]; then
            first=false
        else
            json+=","
        fi
        json+="{\"id\":$id,\"created_at\":\"$created_at\",\"status\":\"$status\","
        json+="\"project_name\":\"$project_name\",\"files_count\":$files_count,"
        json+="\"match_snippet\":\"$match_snippet\",\"rank\":$rank}"
    done <<< "$rows"
    json+="]"

    echo "$json"
}

# Search by status
db_search_by_status() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local status; status=$(_sql_escape "$1")
    local limit; limit=$(_sql_validate_int "${2:-20}" 20)

    local sql="SELECT json_group_array(json_object(
    'id', id,
    'created_at', created_at,
    'project_name', project_name,
    'files_count', files_count,
    'summary', substr(result, 1, 200)
))
FROM (
    SELECT id, created_at, project_name, files_count, result
    FROM reviews
    WHERE status = '$status'
    ORDER BY created_at DESC
    LIMIT $limit
);"
    local result
    if ! result=$(sqlite3 "$db_path" <<< "$sql"); then
        _json_array_fix ""
        return 1
    fi
    _json_array_fix "$result"
}

# ============================================================================
# Insight Operations
# ============================================================================

# Save a structured insight for a review.
# Usage: db_save_insight review_id "type" "what" "why" "file_path" "learned" "severity"
db_save_insight() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id; review_id=$(_sql_validate_int "$1" 0)
    local type; type=$(_sql_escape "$2")
    local what; what=$(_sql_escape "$3")
    local why; why=$(_sql_escape "${4:-}")
    local file_path; file_path=$(_sql_escape "${5:-}")
    local learned; learned=$(_sql_escape "${6:-}")
    local severity; severity=$(_sql_escape "${7:-medium}")

    [[ "$review_id" -eq 0 ]] && { echo "Error: invalid review_id" >&2; return 1; }

    sqlite3 "$db_path" <<SQL
INSERT INTO review_insights (review_id, type, what, why, file_path, learned, severity)
VALUES ($review_id, '$type', '$what', '$why', '$file_path', '$learned', '$severity');
SQL
}

# Get insights for a review, ordered by severity priority.
# Uses CASE expression for correct ordering (critical > high > medium > low).
# Usage: db_get_insights review_id [limit]
db_get_insights() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local review_id; review_id=$(_sql_validate_int "$1" 0)
    local limit; limit=$(_sql_validate_int "${2:-50}" 50)

    local sql="SELECT json_group_array(json_object(
    'id', id,
    'review_id', review_id,
    'type', type,
    'what', what,
    'why', why,
    'file_path', file_path,
    'learned', learned,
    'severity', severity,
    'created_at', created_at
))
FROM (
    SELECT *
    FROM review_insights
    WHERE review_id = $review_id
    ORDER BY
        CASE severity
            WHEN 'critical' THEN 1
            WHEN 'high' THEN 2
            WHEN 'medium' THEN 3
            WHEN 'low' THEN 4
            ELSE 5
        END ASC,
        id ASC
    LIMIT $limit
);"
    _json_array_fix "$(sqlite3 "$db_path" <<< "$sql")"
}

# Full-text search across insights using FTS5 + BM25 ranking.
# Usage: db_search_insights "query" [limit]
db_search_insights() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local query; query=$(_fts5_sanitize "$1")
    local limit; limit=$(_sql_validate_int "${2:-20}" 20)

    [[ -z "$query" ]] && { echo "[]"; return 0; }

    local sep=$'\x1f'
    local rows
    if ! rows=$(sqlite3 -separator "$sep" "$db_path" <<< "SELECT
    ri.id,
    ri.review_id,
    ri.type,
    ri.severity,
    replace(snippet(insights_fts, 0, '>>>', '<<<', '...', 32), char(31), ''),  -- col 0 = what
    bm25(insights_fts)
FROM insights_fts
JOIN review_insights ri ON insights_fts.rowid = ri.id
WHERE insights_fts MATCH '$query'
ORDER BY bm25(insights_fts)
LIMIT $limit;"
    ); then
        echo "[]"
        return 1
    fi

    [[ -z "$rows" ]] && { echo "[]"; return 0; }

    local json="["
    local first=true
    while IFS="$sep" read -r id review_id type severity match_snippet rank; do
        [[ -z "$id" ]] && continue
        match_snippet=$(_json_escape "$match_snippet")
        if [[ "$first" == true ]]; then
            first=false
        else
            json+=","
        fi
        json+="{\"id\":$id,\"review_id\":$review_id,\"type\":\"$type\","
        json+="\"severity\":\"$severity\",\"match_snippet\":\"$match_snippet\",\"rank\":$rank}"
    done <<< "$rows"
    json+="]"
    echo "$json"
}

# Get compact insight summaries for a project (for Engram export or context).
# Usage: db_get_insight_summaries [project] [limit]
db_get_insight_summaries() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local project; project=$(_sql_escape "${1:-}")
    local limit; limit=$(_sql_validate_int "${2:-20}" 20)

    local where_clause=""
    [[ -n "$project" ]] && where_clause="WHERE r.project_name = '$project'"

    local sql="SELECT json_group_array(json_object(
    'type', sub.type,
    'what', sub.what,
    'severity', sub.severity,
    'file_path', sub.file_path,
    'project', sub.project_name,
    'date', sub.created_at
))
FROM (
    SELECT
        ri.type,
        ri.what,
        ri.severity,
        ri.file_path,
        r.project_name,
        ri.created_at
    FROM review_insights ri
    JOIN reviews r ON ri.review_id = r.id
    $where_clause
    ORDER BY ri.created_at DESC
    LIMIT $limit
) sub;"
    _json_array_fix "$(sqlite3 "$db_path" <<< "$sql")"
}

# Extract structured insights from a review result text.
# Parses the AI review output for common patterns and saves as insights.
# Usage: extract_review_insights review_id "result_text" "files"
extract_review_insights() {
    local review_id; review_id=$(_sql_validate_int "$1" 0)
    local result_text="$2"
    local files="${3:-}"

    # Derive default file_path from first non-empty entry in files.
    # Supports both newline-separated and comma-separated formats.
    local file_path=""
    if [[ -n "$files" ]]; then
        while IFS= read -r line; do
            line=${line%%,*}
            line=${line%%$'\r'*}
            if [[ -n "$line" ]]; then
                file_path="$line"
                break
            fi
        done <<< "$files"
    fi

    [[ "$review_id" -eq 0 ]] && return 1
    [[ -z "$result_text" ]] && return 0

    # Strip sensitive data before extracting insights to prevent secrets
    # (API keys, tokens, PEM blobs) from leaking into review_insights table
    result_text=$(_strip_private "$result_text")

    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    [[ ! -f "$db_path" ]] && return 1

    # Check if insights table exists (backward compat)
    local has_table
    has_table=$(sqlite3 "$db_path" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='review_insights';" 2>/dev/null)
    [[ "$has_table" != "1" ]] && return 0

    local lower_result
    lower_result=$(printf '%s' "$result_text" | tr '[:upper:]' '[:lower:]')
    local count=0

    # Security issues
    if echo "$lower_result" | grep -qE '(security|vulnerab|injection|xss|csrf|auth.*bypass)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(security|vulnerab|injection|xss|csrf)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "security" "$what" "" "$file_path" "" "high" 2>/dev/null
            count=$((count + 1))
        }
    fi

    # Bug fixes
    if echo "$lower_result" | grep -qE '(bug|fix|error|crash|null.*pointer|undefined|exception)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(bug|fix|error|crash|null|undefined|exception)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "bugfix" "$what" "" "$file_path" "" "medium" 2>/dev/null
            count=$((count + 1))
        }
    fi

    # Performance issues
    if echo "$lower_result" | grep -qE '(performance|slow|optimize|n\+1|memory leak|latency)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(performance|slow|optimize|n\+1|memory|latency)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "performance" "$what" "" "$file_path" "" "medium" 2>/dev/null
            count=$((count + 1))
        }
    fi

    # Pattern/convention mentions
    if echo "$lower_result" | grep -qE '(pattern|convention|best.?practice|anti.?pattern|code.?smell)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(pattern|convention|best.?practice|anti.?pattern|code.?smell)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "pattern" "$what" "" "$file_path" "" "low" 2>/dev/null
            count=$((count + 1))
        }
    fi

    # Design/decision insights
    if echo "$lower_result" | grep -qE '(decision|decide|decided|chose|chosen|design choice|trade[- ]off|because)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(decision|decide|decided|chose|chosen|design choice|trade[- ]off|because)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "decision" "$what" "" "$file_path" "" "medium" 2>/dev/null
            count=$((count + 1))
        }
    fi

    # Style/nit insights
    if echo "$lower_result" | grep -qE '(style|nit:|naming|name.*convention|formatting|indent|indentation|whitespace|lint|linter)'; then
        local what
        what=$(echo "$result_text" | grep -iE '(style|nit:|naming|name.*convention|formatting|indent|indentation|whitespace|lint|linter)' | head -1 | sed 's/^[[:space:]]*//')
        [[ -n "$what" ]] && {
            db_save_insight "$review_id" "style" "$what" "" "$file_path" "" "low" 2>/dev/null
            count=$((count + 1))
        }
    fi

    echo "$count"
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

    _json_array_fix "$(sqlite3 "$db_path" <<'SQL'
SELECT json_group_array(json_object(
    'project_name', project_name,
    'review_count', review_count,
    'passed', passed,
    'failed', failed,
    'last_review', last_review
))
FROM (
    SELECT
        project_name,
        COUNT(*) as review_count,
        SUM(CASE WHEN status = 'PASSED' THEN 1 ELSE 0 END) as passed,
        SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
        MAX(created_at) as last_review
    FROM reviews
    GROUP BY project_name
    ORDER BY review_count DESC
);
SQL
    )"
}

# ============================================================================
# Maintenance
# ============================================================================

# Delete old reviews (keep last N per project)
db_cleanup() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    local keep; keep=$(_sql_validate_int "${1:-100}" 100)

    local sql="DELETE FROM reviews
WHERE id NOT IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (
            PARTITION BY project_name
            ORDER BY created_at DESC
        ) as rn
        FROM reviews
    )
    WHERE rn <= $keep
);"
    if ! sqlite3 "$db_path" <<< "$sql"; then
        echo "Error: failed to delete old reviews" >&2
        return 1
    fi

    # Vacuum to reclaim space
    if ! sqlite3 "$db_path" "VACUUM;"; then
        echo "Error: VACUUM failed" >&2
        return 1
    fi
}

# Check database integrity
db_check() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    sqlite3 "$db_path" "PRAGMA integrity_check;"
}
