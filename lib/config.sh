#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Configuration Functions
# ============================================================================
# Configuration management via environment variables with sensible defaults.
# Priority: Environment variables (GGA_*) > Defaults
# ============================================================================

# Default values
DEFAULT_DB_PATH="${HOME}/.gga/gga.db"
DEFAULT_HISTORY_LIMIT="50"
DEFAULT_SEARCH_LIMIT="20"

# ============================================================================
# Configuration Functions
# ============================================================================

# Load configuration from environment variables with defaults
load_env_config() {
    GGA_DB_PATH="${GGA_DB_PATH:-$DEFAULT_DB_PATH}"
    GGA_MODEL="${GGA_MODEL:-}"
    GGA_HISTORY_LIMIT="${GGA_HISTORY_LIMIT:-$DEFAULT_HISTORY_LIMIT}"
    GGA_SEARCH_LIMIT="${GGA_SEARCH_LIMIT:-$DEFAULT_SEARCH_LIMIT}"

    # RAG settings (for future iterations)
    GGA_RAG_ENABLED="${GGA_RAG_ENABLED:-true}"
    GGA_RAG_CONTEXT_LIMIT="${GGA_RAG_CONTEXT_LIMIT:-5}"
    GGA_RAG_MIN_SIMILARITY="${GGA_RAG_MIN_SIMILARITY:-0.5}"

    # Ensure database directory exists
    local db_dir
    db_dir=$(dirname "$GGA_DB_PATH")
    [[ ! -d "$db_dir" ]] && mkdir -p "$db_dir"

    # Export for use in subshells
    export GGA_DB_PATH
    export GGA_MODEL
    export GGA_HISTORY_LIMIT
    export GGA_SEARCH_LIMIT
    export GGA_RAG_ENABLED
    export GGA_RAG_CONTEXT_LIMIT
    export GGA_RAG_MIN_SIMILARITY
}

# Get a configuration value by key with optional default
get_config() {
    local key="$1"
    local default="${2:-}"
    local env_var="GGA_${key}"
    local value="${!env_var:-}"
    echo "${value:-$default}"
}

# Set a configuration value (runtime only, not persisted)
set_config() {
    local key="$1"
    local value="$2"
    local env_var="GGA_${key}"
    export "$env_var"="$value"
}

# Validate configuration and dependencies
validate_config() {
    local errors=0

    # Check sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        echo "Error: sqlite3 not found. Please install sqlite3." >&2
        ((errors++))
    fi

    # Check jq is available (needed for JSON processing)
    if ! command -v jq &> /dev/null; then
        echo "Warning: jq not found. Some features may be limited." >&2
    fi

    # Check database directory is writable
    local db_dir
    db_dir=$(dirname "$GGA_DB_PATH")
    if [[ ! -d "$db_dir" ]]; then
        if ! mkdir -p "$db_dir" 2>/dev/null; then
            echo "Error: Cannot create database directory: $db_dir" >&2
            ((errors++))
        fi
    elif [[ ! -w "$db_dir" ]]; then
        echo "Error: Cannot write to database directory: $db_dir" >&2
        ((errors++))
    fi

    return $errors
}

# Display current configuration (for debugging)
show_config() {
    echo "GGA Configuration:"
    echo "  DB_PATH:           $GGA_DB_PATH"
    echo "  MODEL:             ${GGA_MODEL:-<not set>}"
    echo "  HISTORY_LIMIT:     $GGA_HISTORY_LIMIT"
    echo "  SEARCH_LIMIT:      $GGA_SEARCH_LIMIT"
    echo "  RAG_ENABLED:       $GGA_RAG_ENABLED"
    echo "  RAG_CONTEXT_LIMIT: $GGA_RAG_CONTEXT_LIMIT"
}
