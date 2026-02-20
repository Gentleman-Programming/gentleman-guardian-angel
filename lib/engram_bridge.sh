#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Engram Bridge (Optional)
# ============================================================================
# Unidirectional export of GGA review insights to Engram memory format.
# Engram (github.com/Gentleman-Programming/engram) uses a different memory
# model. This bridge exports GGA insights as Engram-compatible observations
# without creating a dependency on Engram.
#
# Usage: Source this file and call engram_export_* functions.
# Requires: jq (for JSON formatting)
# ============================================================================

# Configuration
ENGRAM_ENABLED="${GGA_ENGRAM_ENABLED:-false}"
ENGRAM_OUTPUT_DIR="${GGA_ENGRAM_OUTPUT_DIR:-}"

# ============================================================================
# Type Mapping
# ============================================================================

# Map GGA insight types to Engram observation categories
# GGA types: bugfix, security, pattern, decision, style, performance
# Engram categories: observation, decision, pattern, insight
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

# Map GGA severity to Engram strength (0.0-1.0)
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
# Export Functions
# ============================================================================

# Export a single GGA insight as Engram JSON
# Usage: engram_format_insight "type" "what" "file_path" "severity" [project]
# Returns: JSON string in Engram observation format
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

    # Build JSON (jq-free for minimal dependency)
    local json="{"
    json+="\"category\":\"$engram_category\","
    json+="\"content\":\"$(echo "$what" | sed 's/"/\\"/g')\","
    json+="\"strength\":$engram_strength,"
    json+="\"source\":\"gga\","
    json+="\"metadata\":{"
    json+="\"gga_type\":\"$type\","
    json+="\"severity\":\"$severity\""
    [[ -n "$file_path" ]] && json+=",\"file\":\"$file_path\""
    [[ -n "$project" ]] && json+=",\"project\":\"$project\""
    json+="},"
    json+="\"timestamp\":\"$timestamp\""
    json+="}"

    echo "$json"
}

# Export all insights for a review to Engram format
# Usage: engram_export_review "review_id" [output_dir]
# Returns: Number of exported insights
engram_export_review() {
    local review_id="$1"
    local output_dir="${2:-$ENGRAM_OUTPUT_DIR}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$review_id" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Get review project
    local project
    project=$(sqlite3 "$db_path" \
        "SELECT project_name FROM reviews WHERE id = $review_id;" 2>/dev/null | tr -d '\r')

    # Get insights
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
        ((count++))
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

# Export recent insights to Engram format
# Usage: engram_export_recent [days] [output_dir]
engram_export_recent() {
    local days="${1:-7}"
    local output_dir="${2:-$ENGRAM_OUTPUT_DIR}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && {
        echo "No database found" >&2
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
        total=$((total + count))
    done <<< "$review_ids"

    echo "Exported $total insights from last $days days"
}

# Check if Engram bridge is available
# Usage: engram_check
engram_check() {
    if [[ "$ENGRAM_ENABLED" != "true" ]]; then
        echo "Engram bridge disabled (GGA_ENGRAM_ENABLED=false)"
        return 1
    fi

    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"
    [[ ! -f "$db_path" ]] && {
        echo "No GGA database found"
        return 1
    }

    local insight_count
    insight_count=$(sqlite3 "$db_path" \
        "SELECT COUNT(*) FROM review_insights;" 2>/dev/null | tr -d '\r')

    echo "Engram bridge ready: ${insight_count:-0} insights available for export"
    return 0
}
