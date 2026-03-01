#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Engram Bridge (Optional)
# ============================================================================
# Bidirectional integration with Engram persistent memory system.
# - EXPORT: Send GGA review insights to Engram after each review
# - CONSUME: Retrieve relevant context from Engram before reviews
#
# Engram (github.com/Gentleman-Programming/engram) exposes an HTTP API.
# This bridge communicates via curl to localhost:7437 (configurable).
#
# All operations are opt-in (GGA_ENGRAM_ENABLED=true by default) and
# degrade gracefully — if Engram is not running, GGA works normally.
#
# Requires: curl (for HTTP), jq (recommended for JSON encoding)
# ============================================================================

# Configuration is read dynamically from GGA_ENGRAM_* variables (set by
# load_env_config in config.sh) so that runtime changes are honored.

# ============================================================================
# Type Mapping
# ============================================================================

# Map GGA insight types to Engram observation categories.
# GGA types: bugfix, security, pattern, decision, style, performance
# Engram types: observation, decision, pattern, insight
_engram_map_type() {
    local gga_type="$1"
    case "$gga_type" in
        security)    echo "observation" ;;
        bugfix)      echo "observation" ;;
        decision)    echo "decision" ;;
        pattern)     echo "pattern" ;;
        style)       echo "insight" ;;
        performance) echo "observation" ;;
        *)           echo "observation" ;;
    esac
}

# Map GGA severity to Engram strength (0.0-1.0).
_engram_map_strength() {
    local severity="$1"
    case "$severity" in
        critical) echo "1.0" ;;
        high)     echo "0.8" ;;
        medium)   echo "0.5" ;;
        low)      echo "0.3" ;;
        *)        echo "0.5" ;;
    esac
}

# ============================================================================
# Host Validation
# ============================================================================

# Validate GGA_ENGRAM_HOST format to prevent injection attacks.
# Same pattern used for OLLAMA_HOST and LMSTUDIO_HOST in providers.sh.
# Usage: validate_engram_host "$host" || return 0
validate_engram_host() {
    local host="$1"
    # Regex: http or https, followed by hostname (alphanumeric, dots, hyphens),
    # optional port, optional trailing slash
    [[ "$host" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?/?$ ]]
}

# ============================================================================
# URL Encoding Helper
# ============================================================================

# Percent-encode a string for use in URLs.
# Uses jq if available, falls back to printf-based encoding.
_urlencode() {
    local string="$1"
    if command -v jq &>/dev/null; then
        printf '%s' "$string" | jq -sRr @uri
    else
        local length="${#string}"
        local i char
        for (( i = 0; i < length; i++ )); do
            char="${string:i:1}"
            case "$char" in
                [a-zA-Z0-9.~_-]) printf '%s' "$char" ;;
                *) printf '%%%02X' "'$char" ;;
            esac
        done
    fi
}

# ============================================================================
# Export Functions (GGA → Engram)
# ============================================================================

# Format a single GGA insight as Engram-compatible JSON.
# Uses jq for safe encoding when available, _json_escape() fallback.
# Usage: json=$(engram_format_insight "type" "what" "file_path" "severity" [project])
engram_format_insight() {
    local type="$1"
    local what="$2"
    local file_path="${3:-}"
    local severity="${4:-medium}"
    local project="${5:-}"

    [[ -z "$what" ]] && return 1

    local engram_category engram_strength
    engram_category=$(_engram_map_type "$type")
    engram_strength=$(_engram_map_strength "$severity")

    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

    if command -v jq &>/dev/null; then
        jq -n \
            --arg category "$engram_category" \
            --arg content "$what" \
            --argjson strength "$engram_strength" \
            --arg source "gga" \
            --arg gga_type "$type" \
            --arg severity "$severity" \
            --arg file "$file_path" \
            --arg project "$project" \
            --arg timestamp "$timestamp" \
            '{
                category: $category,
                content: $content,
                strength: $strength,
                source: $source,
                metadata: {
                    gga_type: $gga_type,
                    severity: $severity,
                    file: $file,
                    project: $project
                },
                timestamp: $timestamp
            }'
    else
        # Fallback: manual JSON with _json_escape() from sqlite.sh
        local safe_what safe_file safe_project
        safe_what=$(_json_escape "$what")
        safe_file=$(_json_escape "$file_path")
        safe_project=$(_json_escape "$project")

        printf '{"category":"%s","content":"%s","strength":%s,"source":"gga","metadata":{"gga_type":"%s","severity":"%s","file":"%s","project":"%s"},"timestamp":"%s"}' \
            "$engram_category" "$safe_what" "$engram_strength" \
            "$type" "$severity" "$safe_file" "$safe_project" "$timestamp"
    fi
}

# Export all insights for a review to Engram format.
# If output_dir is set, writes to a file. Otherwise prints JSON array.
# Usage: engram_export_review "review_id" [output_dir]
engram_export_review() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Validate review_id as integer (Copilot fix #10)
    local review_id
    review_id=$(_sql_validate_int "$1" 0)
    if [[ "$review_id" -eq 0 ]]; then
        echo "Error: invalid review ID" >&2
        return 1
    fi

    local output_dir="${2:-${GGA_ENGRAM_OUTPUT_DIR:-}}"

    [[ ! -f "$db_path" ]] && { echo "Error: database not found" >&2; return 1; }

    # Get review project
    local project
    project=$(sqlite3 "$db_path" \
        "SELECT project_name FROM reviews WHERE id = $review_id;" 2>/dev/null | tr -d '\r')

    # Get insights for this review
    local insights
    insights=$(sqlite3 -separator '|' "$db_path" \
        "SELECT type, what, file_path, severity FROM review_insights
         WHERE review_id = $review_id;" 2>/dev/null | tr -d '\r')

    [[ -z "$insights" ]] && { echo "0"; return 0; }

    local count=0
    local all_json="["

    while IFS='|' read -r itype iwhat ifile isev; do
        [[ -z "$iwhat" ]] && continue

        local json
        json=$(engram_format_insight "$itype" "$iwhat" "$ifile" "$isev" "$project")

        if [[ $count -gt 0 ]]; then
            all_json+=","
        fi
        all_json+="$json"
        count=$((count + 1))
    done <<< "$insights"

    all_json+="]"

    # Output to directory if specified
    if [[ -n "$output_dir" ]]; then
        mkdir -p "$output_dir"
        local filename="gga_review_${review_id}_$(date +%Y%m%d%H%M%S).json"
        echo "$all_json" > "$output_dir/$filename"
        echo "$count"
    else
        echo "$all_json"
    fi
}

# Export recent insights (last N days).
# Usage: engram_export_recent [days] [output_dir]
engram_export_recent() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Validate days as integer (Copilot fix #11)
    local days
    days=$(_sql_validate_int "${1:-7}" 7)

    local output_dir="${2:-${GGA_ENGRAM_OUTPUT_DIR:-}}"

    [[ ! -f "$db_path" ]] && {
        echo "Error: database not found" >&2
        return 1
    }

    # Get review IDs from the last N days
    local review_ids
    review_ids=$(sqlite3 "$db_path" \
        "SELECT id FROM reviews
         WHERE created_at >= datetime('now', '-$days days')
         ORDER BY id;" 2>/dev/null | tr -d '\r')

    [[ -z "$review_ids" ]] && {
        echo "No reviews in the last $days days"
        return 0
    }

    local total=0
    while IFS= read -r rid; do
        [[ -z "$rid" ]] && continue
        local count
        count=$(engram_export_review "$rid" "$output_dir")
        # Only update total if engram_export_review returned a numeric count
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            total=$((total + count))
        fi
    done <<< "$review_ids"

    echo "Exported $total insights from last $days days"
}

# ============================================================================
# Save to Engram (GGA → Engram HTTP)
# ============================================================================

# Save a single observation to Engram via HTTP API.
# Never fails the calling pipeline — errors are silently ignored.
# Usage: engram_save_observation "title" "type" "content" "project"
engram_save_observation() {
    local title="$1"
    local type="$2"
    local content="$3"
    local project="${4:-}"

    [[ "${GGA_ENGRAM_ENABLED:-true}" != "true" ]] && return 0
    [[ -z "$title" || -z "$content" ]] && return 0
    command -v curl &>/dev/null || return 0

    local engram_host="${GGA_ENGRAM_HOST:-http://localhost:7437}"
    validate_engram_host "$engram_host" || return 0
    local engram_timeout="${GGA_ENGRAM_TIMEOUT:-3}"

    local json
    if command -v jq &>/dev/null; then
        json=$(jq -n \
            --arg title "$title" \
            --arg type "$type" \
            --arg content "$content" \
            --arg project "$project" \
            '{title: $title, type: $type, content: $content,
              project: $project, source: "gga"}')
    else
        local safe_title safe_content safe_project
        safe_title=$(_json_escape "$title")
        safe_content=$(_json_escape "$content")
        safe_project=$(_json_escape "$project")
        json="{\"title\":\"$safe_title\",\"type\":\"$type\",\"content\":\"$safe_content\",\"project\":\"$safe_project\",\"source\":\"gga\"}"
    fi

    curl -s --connect-timeout "$engram_timeout" --max-time "$((engram_timeout * 2))" \
        -X POST "$engram_host/api/save" \
        -H "Content-Type: application/json" \
        -d "$json" \
        &>/dev/null || true
}

# ============================================================================
# Consume Functions (Engram → GGA)
# ============================================================================

# Check if the Engram server is reachable.
# Usage: if engram_is_available; then ...; fi
engram_is_available() {
    [[ "${GGA_ENGRAM_ENABLED:-true}" != "true" ]] && return 1
    command -v curl &>/dev/null || return 1

    local engram_host="${GGA_ENGRAM_HOST:-http://localhost:7437}"
    validate_engram_host "$engram_host" || return 1
    local engram_timeout="${GGA_ENGRAM_TIMEOUT:-3}"

    curl -s --connect-timeout "$engram_timeout" --max-time "$engram_timeout" \
        "$engram_host/api/stats" &>/dev/null
}

# Search Engram memory for relevant observations.
# Usage: results=$(engram_search "query terms" [project])
engram_search() {
    local query="$1"
    local project="${2:-}"

    [[ "${GGA_ENGRAM_ENABLED:-true}" != "true" ]] && return 0
    [[ -z "$query" ]] && return 0
    command -v curl &>/dev/null || return 0

    local engram_host="${GGA_ENGRAM_HOST:-http://localhost:7437}"
    validate_engram_host "$engram_host" || return 0
    local engram_timeout="${GGA_ENGRAM_TIMEOUT:-3}"
    local engram_context_limit="${GGA_ENGRAM_CONTEXT_LIMIT:-5}"

    local url="$engram_host/api/search?q=$(_urlencode "$query")&limit=$engram_context_limit"
    [[ -n "$project" ]] && url+="&project=$(_urlencode "$project")"

    local results
    results=$(curl -s --connect-timeout "$engram_timeout" --max-time "$((engram_timeout * 2))" \
        "$url" 2>/dev/null) || return 0

    [[ -z "$results" || "$results" == "null" || "$results" == "[]" ]] && return 0
    echo "$results"
}

# Get review context from Engram based on files being reviewed.
# Extracts basenames from file list, searches Engram for relevant memories,
# and returns compact formatted context suitable for prompt injection.
#
# Relevance strategy:
#   1. Filter by project name (mandatory)
#   2. Search by file basenames (FTS5 + BM25 ranking in Engram)
#   3. Limit to ENGRAM_CONTEXT_LIMIT entries (~500 tokens max)
#
# Usage: context=$(engram_get_review_context "file1.ts\nfile2.ts" "project-name")
engram_get_review_context() {
    local files="$1"
    local project="$2"

    [[ "${GGA_ENGRAM_ENABLED:-true}" != "true" ]] && return 0
    [[ -z "$files" ]] && return 0
    command -v curl &>/dev/null || return 0
    command -v jq &>/dev/null || return 0

    # Check Engram is reachable (fast fail)
    engram_is_available || return 0

    # Extract basenames from file list for search terms
    local search_terms
    search_terms=$(echo "$files" | while IFS= read -r f; do
        [[ -n "$f" ]] && basename "$f"
    done | tr '\n' ' ' | sed 's/ *$//')

    [[ -z "$search_terms" ]] && return 0

    # Search Engram
    local results
    results=$(engram_search "$search_terms" "$project") || return 0
    [[ -z "$results" ]] && return 0

    # Format as compact context lines for prompt injection
    echo "$results" | jq -r '
        if type == "array" then
            .[] |
            "- [\(.type // .category // "observation")] \(.title // (.content | .[0:200])) (\(.created_at // .timestamp | split("T")[0] // "recent"))"
        elif type == "object" and has("results") then
            .results[] |
            "- [\(.type // .category // "observation")] \(.title // (.content | .[0:200])) (\(.created_at // .timestamp | split("T")[0] // "recent"))"
        else
            empty
        end
    ' 2>/dev/null
}

# ============================================================================
# Status
# ============================================================================

# Check Engram bridge status and report.
# Usage: engram_check
engram_check() {
    local engram_enabled="${GGA_ENGRAM_ENABLED:-true}"
    local engram_host="${GGA_ENGRAM_HOST:-http://localhost:7437}"

    if [[ "$engram_enabled" != "true" ]]; then
        echo "Engram bridge disabled (GGA_ENGRAM_ENABLED=false)"
        return 1
    fi

    if ! validate_engram_host "$engram_host"; then
        echo "Error: invalid GGA_ENGRAM_HOST format. Expected: http(s)://hostname(:port)"
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        echo "Error: curl not found (required for Engram bridge)"
        return 1
    fi

    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    if engram_is_available; then
        local insight_count="0"
        if [[ -f "$db_path" ]]; then
            insight_count=$(sqlite3 "$db_path" \
                "SELECT COUNT(*) FROM review_insights;" 2>/dev/null | tr -d '\r')
            insight_count="${insight_count:-0}"
        fi
        echo "Engram bridge ready at $engram_host (${insight_count} local insights available)"
        return 0
    else
        echo "Engram server not reachable at $engram_host"
        echo "Start with: engram serve"
        return 1
    fi
}
