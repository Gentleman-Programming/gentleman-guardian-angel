#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Embeddings (Multi-Provider)
# ============================================================================
# Generates embeddings for semantic search using multiple providers.
# Supports: OpenAI, Gemini, Ollama (local), GitHub Models
# ============================================================================

# ============================================================================
# Provider: OpenAI
# ============================================================================

embed_openai() {
    local text="$1"
    local model="${GGA_OPENAI_EMBED_MODEL:-text-embedding-3-small}"
    local api_key="${OPENAI_API_KEY:-}"

    [[ -z "$api_key" ]] && return 1
    [[ -z "$text" ]] && return 1

    local payload response
    payload=$(jq -n --arg text "$text" --arg model "$model" '{
        model: $model,
        input: $text
    }')

    response=$(curl -s --max-time 30 "https://api.openai.com/v1/embeddings" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    echo "$response" | jq -c '.data[0].embedding // empty' 2>/dev/null
}

# ============================================================================
# Provider: Gemini
# ============================================================================

embed_gemini() {
    local text="$1"
    local model="${GGA_GEMINI_EMBED_MODEL:-text-embedding-004}"
    local api_key="${GOOGLE_API_KEY:-}"

    [[ -z "$api_key" ]] && return 1
    [[ -z "$text" ]] && return 1

    local payload response
    payload=$(jq -n --arg text "$text" '{
        content: {parts: [{text: $text}]}
    }')

    response=$(curl -s --max-time 30 \
        "https://generativelanguage.googleapis.com/v1/models/${model}:embedContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    echo "$response" | jq -c '.embedding.values // empty' 2>/dev/null
}

# ============================================================================
# Provider: Ollama (Local)
# ============================================================================

embed_ollama() {
    local text="$1"
    local model="${GGA_OLLAMA_EMBED_MODEL:-nomic-embed-text}"
    local host="${OLLAMA_HOST:-http://localhost:11434}"

    [[ -z "$text" ]] && return 1

    # Check Ollama is available
    curl -s --max-time 2 "${host}/api/tags" >/dev/null 2>&1 || return 1

    local payload response
    payload=$(jq -n --arg text "$text" --arg model "$model" '{
        model: $model,
        prompt: $text
    }')

    response=$(curl -s --max-time 60 "${host}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    echo "$response" | jq -c '.embedding // empty' 2>/dev/null
}

# ============================================================================
# Provider: GitHub Models (Azure)
# ============================================================================

embed_github_models() {
    local text="$1"
    local model="${GGA_GITHUB_EMBED_MODEL:-text-embedding-3-small}"
    local token="${GITHUB_TOKEN:-}"

    [[ -z "$token" ]] && return 1
    [[ -z "$text" ]] && return 1

    local payload response
    payload=$(jq -n --arg text "$text" --arg model "$model" '{
        model: $model,
        input: [$text]
    }')

    response=$(curl -s --max-time 30 "https://models.inference.ai.azure.com/embeddings" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    echo "$response" | jq -c '.data[0].embedding // empty' 2>/dev/null
}

# ============================================================================
# Unified Embedding Function with Fallback Chain
# ============================================================================

# Get embedding using configured provider or fallback chain
# Usage: get_embedding "text to embed"
# Returns: JSON array of floats or empty string on failure
get_embedding() {
    local text="$1"
    local provider="${GGA_EMBED_PROVIDER:-auto}"

    [[ -z "$text" ]] && return 1

    # Specific provider requested
    if [[ "$provider" != "auto" ]]; then
        case "$provider" in
            openai) embed_openai "$text" ;;
            gemini) embed_gemini "$text" ;;
            ollama) embed_ollama "$text" ;;
            github-models|github) embed_github_models "$text" ;;
            *) echo ""; return 1 ;;
        esac
        return $?
    fi

    # Auto mode: Fallback chain (Ollama -> Gemini -> GitHub -> OpenAI)
    # Ollama first (free, local)
    local embedding
    embedding=$(embed_ollama "$text")
    [[ -n "$embedding" && "$embedding" != "null" && "$embedding" != "" ]] && { echo "$embedding"; return 0; }

    # Gemini (free tier available)
    embedding=$(embed_gemini "$text")
    [[ -n "$embedding" && "$embedding" != "null" && "$embedding" != "" ]] && { echo "$embedding"; return 0; }

    # GitHub Models (included with GitHub)
    embedding=$(embed_github_models "$text")
    [[ -n "$embedding" && "$embedding" != "null" && "$embedding" != "" ]] && { echo "$embedding"; return 0; }

    # OpenAI (paid)
    embedding=$(embed_openai "$text")
    [[ -n "$embedding" && "$embedding" != "null" && "$embedding" != "" ]] && { echo "$embedding"; return 0; }

    # All providers failed
    echo ""
    return 1
}

# ============================================================================
# Embedding Storage
# ============================================================================

# Save embedding to database for a review
# Usage: save_embedding review_id embedding_json
save_embedding() {
    local review_id="$1"
    local embedding="$2"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$review_id" || -z "$embedding" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Store as blob
    sqlite3 "$db_path" "UPDATE reviews SET embedding = '$embedding' WHERE id = $review_id;"
}

# Get embedding for a review
# Usage: get_review_embedding review_id
get_review_embedding() {
    local review_id="$1"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$review_id" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    sqlite3 "$db_path" "SELECT embedding FROM reviews WHERE id = $review_id;" | tr -d '\r'
}

# Generate and store embedding for a review's content
# Usage: embed_review review_id
embed_review() {
    local review_id="$1"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$review_id" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Get review content to embed
    local content
    content=$(sqlite3 "$db_path" "SELECT files || ' ' || COALESCE(result, '') FROM reviews WHERE id = $review_id;")

    [[ -z "$content" ]] && return 1

    # Generate embedding
    local embedding
    embedding=$(get_embedding "$content")

    [[ -z "$embedding" ]] && return 1

    # Store it
    save_embedding "$review_id" "$embedding"
}
