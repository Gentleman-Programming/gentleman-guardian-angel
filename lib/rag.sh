#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - RAG (Retrieval Augmented Generation)
# ============================================================================
# Provides context-aware code reviews by retrieving relevant historical
# reviews and augmenting prompts with project-specific knowledge.
# ============================================================================

# Configuration
RAG_ENABLED="${GGA_RAG_ENABLED:-true}"
RAG_CONTEXT_LIMIT="${GGA_RAG_CONTEXT_LIMIT:-5}"
RAG_MIN_SIMILARITY="${GGA_RAG_MIN_SIMILARITY:-0.3}"
RAG_MAX_TOKENS="${GGA_RAG_MAX_TOKENS:-2000}"
RAG_RECENCY_BOOST="${GGA_RAG_RECENCY_BOOST:-0.1}"
RAG_RECENCY_DAYS="${GGA_RAG_RECENCY_DAYS:-30}"

# ============================================================================
# Pattern Extraction
# ============================================================================

# Extract patterns from code for context search
# Usage: rag_extract_patterns "files" "diff" "commit_msg"
# Returns: Space-separated list of detected patterns/concepts
rag_extract_patterns() {
    local files="$1"
    local diff="$2"
    local commit_msg="${3:-}"

    local patterns=()

    # Include file names as context
    [[ -n "$files" ]] && patterns+=("$files")

    # Detect patterns in diff
    if [[ -n "$diff" ]]; then
        # Authentication patterns
        echo "$diff" | grep -qiE '(auth|login|logout|token|jwt|session|password|credential)' && \
            patterns+=("authentication security")

        # Database patterns
        echo "$diff" | grep -qiE '(sql|query|database|db\.|select|insert|update|delete|join)' && \
            patterns+=("database query")

        # API patterns
        echo "$diff" | grep -qiE '(api|endpoint|http|fetch|axios|request|response|rest|graphql)' && \
            patterns+=("api endpoint")

        # Security patterns
        echo "$diff" | grep -qiE '(xss|injection|sanitize|escape|csrf|cors|encrypt|decrypt)' && \
            patterns+=("security vulnerability")

        # Validation patterns
        echo "$diff" | grep -qiE '(valid|schema|zod|yup|joi|assert|check|verify)' && \
            patterns+=("validation")

        # Error handling patterns
        echo "$diff" | grep -qiE '(error|exception|try|catch|throw|finally|reject)' && \
            patterns+=("error handling")
    fi

    # Include commit message
    [[ -n "$commit_msg" ]] && patterns+=("$commit_msg")

    echo "${patterns[*]}"
}

# ============================================================================
# Retrieval with Recency Boost
# ============================================================================

# Retrieve similar reviews with recency boost
# Usage: rag_retrieve "query" [project] [limit]
# Returns: Pipe-separated results: boosted_score|id|project|summary
rag_retrieve() {
    local query="$1"
    local project="${2:-}"
    local limit="${3:-$RAG_CONTEXT_LIMIT}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$query" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Source semantic search
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./semantic.sh
    source "$lib_dir/semantic.sh" 2>/dev/null || return 1

    # Get initial results (fetch more than needed for filtering)
    local results
    results=$(search_hybrid "$query" 0.5 "$((limit * 3))")

    [[ -z "$results" ]] && return 0

    local now boosted=()
    now=$(date +%s)

    while IFS='|' read -r score id status proj snippet; do
        [[ -z "$id" ]] && continue

        # Filter by project if specified
        if [[ -n "$project" && "$proj" != "$project" ]]; then
            continue
        fi

        # Get review timestamp
        local timestamp
        timestamp=$(sqlite3 "$db_path" \
            "SELECT created_at FROM reviews WHERE id = $id;" 2>/dev/null | tr -d '\r')

        # Calculate recency boost
        local review_time age_days recency_mult boosted_score
        if [[ -n "$timestamp" ]]; then
            # Try to parse timestamp
            review_time=$(date -d "$timestamp" +%s 2>/dev/null) || review_time=$now
        else
            review_time=$now
        fi

        age_days=$(( (now - review_time) / 86400 ))

        # Apply recency boost for recent reviews
        if [[ $age_days -lt $RAG_RECENCY_DAYS ]]; then
            # Linear decay: full boost at day 0, no boost at RAG_RECENCY_DAYS
            recency_mult=$(awk -v boost="$RAG_RECENCY_BOOST" -v age="$age_days" -v days="$RAG_RECENCY_DAYS" \
                'BEGIN { printf "%.4f", 1.0 + boost * (1 - age / days) }')
        else
            recency_mult="1.0"
        fi

        boosted_score=$(awk -v score="$score" -v mult="$recency_mult" \
            'BEGIN { printf "%.4f", score * mult }')

        # Filter by minimum similarity
        if awk -v bs="$boosted_score" -v min="$RAG_MIN_SIMILARITY" \
            'BEGIN { exit (bs >= min) ? 0 : 1 }'; then
            boosted+=("$boosted_score|$id|$proj|$snippet")
        fi
    done <<< "$results"

    # Sort by boosted score and limit
    printf '%s\n' "${boosted[@]}" | sort -t'|' -k1 -rn | head -n "$limit"
}

# ============================================================================
# Context Building
# ============================================================================

# Build markdown context from retrieved reviews
# Usage: rag_build_context "retrieved_results"
# Returns: Formatted markdown context string
rag_build_context() {
    local retrieved="$1"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$retrieved" ]] && return 0
    [[ ! -f "$db_path" ]] && return 0

    local context=""
    local token_count=0
    local review_num=0

    while IFS='|' read -r score id proj snippet; do
        [[ -z "$id" ]] && continue

        # Get review details
        local details status result files
        details=$(sqlite3 -separator '|' "$db_path" \
            "SELECT status, result, files FROM reviews WHERE id = $id;" 2>/dev/null | tr -d '\r')

        IFS='|' read -r status result files <<< "$details"

        # Truncate long results
        if [[ ${#result} -gt 400 ]]; then
            result="${result:0:400}..."
        fi

        # Check token budget (approximate: 1 token ~ 4 chars)
        local entry_tokens=$(( ${#result} / 4 + 50 ))
        if [[ $((token_count + entry_tokens)) -gt $RAG_MAX_TOKENS ]]; then
            break
        fi

        ((review_num++))
        token_count=$((token_count + entry_tokens))

        # Format entry
        local pct
        pct=$(awk -v s="$score" 'BEGIN { printf "%.0f", s * 100 }')

        context+="
### Review #$review_num (Relevancia: ${pct}%)
- **Estado:** $status
- **Archivos:** $files
- **Hallazgos:** $result
---"
    done <<< "$retrieved"

    echo "$context"
}

# ============================================================================
# Prompt Augmentation
# ============================================================================

# Augment prompt with historical context
# Usage: rag_augment_prompt "original_prompt" "files" "diff" [commit_msg]
# Returns: Augmented prompt or original if RAG doesn't apply
rag_augment_prompt() {
    local original_prompt="$1"
    local files="$2"
    local diff="$3"
    local commit_msg="${4:-}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Check if RAG is enabled
    [[ "$RAG_ENABLED" != "true" ]] && { echo "$original_prompt"; return 0; }

    # Check database exists
    [[ ! -f "$db_path" ]] && { echo "$original_prompt"; return 0; }

    # Check sufficient history (minimum 3 reviews)
    local review_count
    review_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM reviews;" 2>/dev/null | tr -d '\r')
    [[ -z "$review_count" || $review_count -lt 3 ]] && { echo "$original_prompt"; return 0; }

    # Extract patterns from current code
    local query
    query=$(rag_extract_patterns "$files" "$diff" "$commit_msg")
    [[ -z "$query" ]] && { echo "$original_prompt"; return 0; }

    # Retrieve similar reviews
    local retrieved
    retrieved=$(rag_retrieve "$query")
    [[ -z "$retrieved" ]] && { echo "$original_prompt"; return 0; }

    # Build context
    local context
    context=$(rag_build_context "$retrieved")
    [[ -z "$context" ]] && { echo "$original_prompt"; return 0; }

    # Assemble augmented prompt
    cat <<EOF
$original_prompt

---
## Contexto Historico del Proyecto

Las siguientes son reviews anteriores relevantes para el codigo actual:
$context

**Instrucciones adicionales:**
- Considera este contexto historico al revisar el codigo
- Si encuentras patrones similares a problemas anteriores, mencionalos
- Mantiene consistencia con decisiones y soluciones pasadas
- Aplica lecciones aprendidas de reviews anteriores
EOF
}

# ============================================================================
# RAG Ask - Query Historical Reviews
# ============================================================================

# Answer questions using review history
# Usage: rag_ask "question" [project]
# Returns: Answer based on historical context
rag_ask() {
    local question="$1"
    local project="${2:-}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$question" ]] && {
        echo "Uso: gga ask \"tu pregunta\"" >&2
        return 1
    }

    [[ ! -f "$db_path" ]] && {
        echo "No hay historial de reviews. Ejecuta 'gga run' primero." >&2
        return 1
    }

    # Retrieve relevant reviews
    local retrieved
    retrieved=$(rag_retrieve "$question" "$project" 10)

    [[ -z "$retrieved" ]] && {
        echo "No se encontro contexto historico relevante para tu pregunta."
        return 0
    }

    # Build context
    local context
    context=$(rag_build_context "$retrieved")

    # Return formatted response (actual LLM call would be in CLI)
    cat <<EOF
## Contexto Relevante del Historial

Basado en tu pregunta: "$question"

Se encontraron las siguientes reviews relacionadas:
$context

Para obtener una respuesta detallada, usa un proveedor AI:
  GGA_PROVIDER=claude gga ask "$question"
EOF
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if RAG is available and has sufficient data
# Usage: rag_check
# Returns: 0 if RAG can be used, 1 otherwise
rag_check() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ "$RAG_ENABLED" != "true" ]] && {
        echo "RAG deshabilitado (GGA_RAG_ENABLED=false)"
        return 1
    }

    [[ ! -f "$db_path" ]] && {
        echo "Base de datos no encontrada: $db_path"
        return 1
    }

    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM reviews;" 2>/dev/null | tr -d '\r')

    if [[ -z "$count" || $count -lt 3 ]]; then
        echo "Historial insuficiente: $count reviews (minimo: 3)"
        return 1
    fi

    echo "RAG disponible: $count reviews en historial"
    return 0
}

# Get RAG statistics
# Usage: rag_stats
rag_stats() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && {
        echo "No hay base de datos"
        return 1
    }

    local total passed failed
    total=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM reviews;" 2>/dev/null | tr -d '\r')
    passed=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM reviews WHERE status='PASSED';" 2>/dev/null | tr -d '\r')
    failed=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM reviews WHERE status='FAILED';" 2>/dev/null | tr -d '\r')

    cat <<EOF
RAG Stats:
  Total Reviews: $total
  Passed: $passed
  Failed: $failed
  RAG Enabled: $RAG_ENABLED
  Min Similarity: $RAG_MIN_SIMILARITY
  Context Limit: $RAG_CONTEXT_LIMIT
EOF
}
