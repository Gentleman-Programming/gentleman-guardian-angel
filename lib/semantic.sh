#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Semantic Search
# ============================================================================
# Provides hybrid search combining FTS5 (lexical) with embeddings (semantic).
# ============================================================================

# Default search parameters
SEARCH_ALPHA="${GGA_SEARCH_ALPHA:-0.5}"      # Balance: 0=semantic, 1=lexical
SEARCH_LIMIT="${GGA_SEARCH_LIMIT:-20}"
SEMANTIC_MIN_SIMILARITY="${GGA_SEMANTIC_MIN_SIMILARITY:-0.3}"

# ============================================================================
# Cosine Similarity
# ============================================================================

# Calculate cosine similarity between two embedding vectors
# Usage: cosine_similarity '[0.1,0.2,...]' '[0.3,0.4,...]'
# Returns: Float between -1 and 1 (usually 0 to 1 for normalized embeddings)
cosine_similarity() {
    local vec1="$1"
    local vec2="$2"

    [[ -z "$vec1" || -z "$vec2" ]] && { echo "0"; return 1; }
    [[ "$vec1" == "null" || "$vec2" == "null" ]] && { echo "0"; return 1; }

    # Use awk for fast computation
    paste <(echo "$vec1" | jq -r '.[]' 2>/dev/null) \
          <(echo "$vec2" | jq -r '.[]' 2>/dev/null) 2>/dev/null | \
    awk '
    BEGIN { dot = 0; norm1 = 0; norm2 = 0 }
    {
        dot += $1 * $2
        norm1 += $1 * $1
        norm2 += $2 * $2
    }
    END {
        if (norm1 > 0 && norm2 > 0) {
            printf "%.6f", dot / (sqrt(norm1) * sqrt(norm2))
        } else {
            print "0"
        }
    }'
}

# ============================================================================
# Lexical Search (FTS5)
# ============================================================================

# Search using FTS5 full-text search
# Usage: search_lexical "query" [limit]
# Returns: pipe-separated results: id|status|score|snippet
search_lexical() {
    local query="$1"
    local limit="${2:-$SEARCH_LIMIT}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$query" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Escape single quotes for SQL
    query="${query//\'/\'\'}"

    sqlite3 -separator '|' "$db_path" <<SQL
SELECT
    r.id,
    r.status,
    r.project_name,
    printf('%.4f', 1.0 / (1.0 + abs(rank))) as score,
    snippet(reviews_fts, 1, '>>>', '<<<', '...', 32) as snippet
FROM reviews_fts
JOIN reviews r ON reviews_fts.rowid = r.id
WHERE reviews_fts MATCH '$query'
ORDER BY rank
LIMIT $limit;
SQL
}

# ============================================================================
# Semantic Search (Embeddings)
# ============================================================================

# Search using embedding similarity
# Usage: search_semantic "query" [limit]
# Returns: pipe-separated results: score|id|status|project
search_semantic() {
    local query="$1"
    local limit="${2:-$SEARCH_LIMIT}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$query" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Source embeddings if not already loaded
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./embeddings.sh
    source "$lib_dir/embeddings.sh" 2>/dev/null || true

    # Get query embedding
    local query_embedding
    query_embedding=$(get_embedding "$query")

    if [[ -z "$query_embedding" || "$query_embedding" == "null" ]]; then
        # Fallback to lexical if embedding fails
        return 1
    fi

    # Get all reviews with embeddings and calculate similarity
    local results=()
    while IFS='|' read -r id status project emb_blob; do
        [[ -z "$id" || -z "$emb_blob" || "$emb_blob" == "null" ]] && continue

        local sim
        sim=$(cosine_similarity "$query_embedding" "$emb_blob")

        # Filter by minimum similarity
        if (( $(echo "$sim >= $SEMANTIC_MIN_SIMILARITY" | bc -l 2>/dev/null || echo 0) )); then
            results+=("$sim|$id|$status|$project")
        fi
    done < <(sqlite3 -separator '|' "$db_path" \
        "SELECT id, status, project_name, embedding FROM reviews WHERE embedding IS NOT NULL AND embedding != '';")

    # Sort by similarity descending and limit
    printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn | head -n "$limit"
}

# ============================================================================
# Hybrid Search
# ============================================================================

# Combine lexical and semantic search
# Usage: search_hybrid "query" [alpha] [limit]
# alpha: 0.0 = pure semantic, 1.0 = pure lexical, 0.5 = balanced
# Returns: pipe-separated results: score|id|status|project|snippet
search_hybrid() {
    local query="$1"
    local alpha="${2:-$SEARCH_ALPHA}"
    local limit="${3:-$SEARCH_LIMIT}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$query" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Associative arrays for combining scores
    declare -A lexical_scores
    declare -A semantic_scores
    declare -A statuses
    declare -A projects
    declare -A snippets

    # Get lexical results
    while IFS='|' read -r id status project score snippet; do
        [[ -z "$id" ]] && continue
        lexical_scores[$id]="$score"
        statuses[$id]="$status"
        projects[$id]="$project"
        snippets[$id]="$snippet"
    done < <(search_lexical "$query" "$((limit * 2))")

    # Get semantic results
    while IFS='|' read -r score id status project; do
        [[ -z "$id" ]] && continue
        semantic_scores[$id]="$score"
        statuses[$id]="$status"
        projects[$id]="$project"
    done < <(search_semantic "$query" "$((limit * 2))" 2>/dev/null)

    # Combine all IDs
    declare -A all_ids
    for id in "${!lexical_scores[@]}"; do all_ids[$id]=1; done
    for id in "${!semantic_scores[@]}"; do all_ids[$id]=1; done

    # Calculate hybrid scores
    local results=()
    for id in "${!all_ids[@]}"; do
        local lex_score="${lexical_scores[$id]:-0}"
        local sem_score="${semantic_scores[$id]:-0}"

        # Hybrid formula: alpha * lexical + (1-alpha) * semantic
        local hybrid_score
        hybrid_score=$(awk -v a="$alpha" -v l="$lex_score" -v s="$sem_score" \
            'BEGIN { printf "%.4f", a * l + (1-a) * s }')

        local status="${statuses[$id]:-UNKNOWN}"
        local project="${projects[$id]:-unknown}"
        local snippet="${snippets[$id]:-}"

        results+=("$hybrid_score|$id|$status|$project|$snippet")
    done

    # Sort by score and limit
    printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn | head -n "$limit"
}

# ============================================================================
# Similar Reviews
# ============================================================================

# Find reviews similar to a given review ID
# Usage: find_similar review_id [limit]
find_similar() {
    local review_id="$1"
    local limit="${2:-5}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$review_id" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Get the review's embedding
    local target_embedding
    target_embedding=$(sqlite3 "$db_path" "SELECT embedding FROM reviews WHERE id = $review_id;")

    if [[ -z "$target_embedding" || "$target_embedding" == "null" ]]; then
        echo "Review $review_id has no embedding" >&2
        return 1
    fi

    # Compare with all other reviews
    local results=()
    while IFS='|' read -r id status project emb_blob; do
        [[ -z "$id" || "$id" == "$review_id" ]] && continue
        [[ -z "$emb_blob" || "$emb_blob" == "null" ]] && continue

        local sim
        sim=$(cosine_similarity "$target_embedding" "$emb_blob")

        if (( $(echo "$sim >= $SEMANTIC_MIN_SIMILARITY" | bc -l 2>/dev/null || echo 0) )); then
            results+=("$sim|$id|$status|$project")
        fi
    done < <(sqlite3 -separator '|' "$db_path" \
        "SELECT id, status, project_name, embedding FROM reviews WHERE embedding IS NOT NULL AND id != $review_id;")

    # Sort and limit
    printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn | head -n "$limit"
}
