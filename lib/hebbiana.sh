#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Hebbian Memory
# ============================================================================
# "Neurons that fire together, wire together" - Donald Hebb, 1949
#
# GGA learns patterns from your review history and predicts issues before
# they occur by building associative memory between concepts.
# ============================================================================

# Configuration
HEBBIAN_ENABLED="${GGA_HEBBIAN_ENABLED:-true}"
HEBBIAN_LEARNING_RATE="${GGA_HEBBIAN_LEARNING_RATE:-0.1}"
HEBBIAN_DECAY_RATE="${GGA_HEBBIAN_DECAY_RATE:-0.99}"
HEBBIAN_THRESHOLD="${GGA_HEBBIAN_THRESHOLD:-0.1}"
HEBBIAN_SPREAD_ITERATIONS="${GGA_HEBBIAN_SPREAD_ITERATIONS:-3}"
HEBBIAN_SPREAD_DECAY="${GGA_HEBBIAN_SPREAD_DECAY:-0.5}"

# ============================================================================
# Schema Initialization
# ============================================================================

# Initialize Hebbian tables in database
hebbian_init_schema() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && return 1

    sqlite3 "$db_path" <<'SQL'
-- Concepts detected in reviews
CREATE TABLE IF NOT EXISTS concepts (
    id TEXT PRIMARY KEY,           -- "pattern:auth", "file:login.ts"
    type TEXT NOT NULL,            -- pattern, file, error, keyword
    frequency INTEGER DEFAULT 1,
    last_seen TEXT DEFAULT (datetime('now'))
);

-- Associations between concepts (Hebbian weights)
CREATE TABLE IF NOT EXISTS associations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    concept_a TEXT NOT NULL,
    concept_b TEXT NOT NULL,
    weight REAL DEFAULT 0.5,       -- [0.0, 1.0]
    co_occurrences INTEGER DEFAULT 1,
    context TEXT DEFAULT 'review', -- review, file, error
    last_updated TEXT DEFAULT (datetime('now')),
    UNIQUE(concept_a, concept_b, context)
);

CREATE INDEX IF NOT EXISTS idx_assoc_a ON associations(concept_a);
CREATE INDEX IF NOT EXISTS idx_assoc_b ON associations(concept_b);
CREATE INDEX IF NOT EXISTS idx_assoc_weight ON associations(weight DESC);
CREATE INDEX IF NOT EXISTS idx_concepts_type ON concepts(type);
SQL
}

# ============================================================================
# Concept Extraction
# ============================================================================

# Extract concepts from text (code, diff, review result)
# Usage: hebbian_extract_concepts "text"
# Returns: One concept per line in format "type:name"
hebbian_extract_concepts() {
    local text="$1"
    local concepts=()

    [[ -z "$text" ]] && return 0

    # Pattern definitions: "name:regex"
    local patterns=(
        "authentication:auth|login|logout|session|token|jwt|oauth|password|credential"
        "security:security|xss|injection|csrf|sanitize|escape|encrypt|decrypt|cors"
        "database:sql|query|database|db|postgres|mysql|sqlite|select|insert|update|delete"
        "api:api|endpoint|rest|graphql|http|request|response|fetch|axios"
        "validation:validate|validation|input|schema|zod|yup|joi|assert"
        "error:error|exception|catch|throw|fail|reject|try|finally"
        "testing:test|spec|mock|stub|jest|mocha|pytest|unittest"
        "performance:perf|performance|cache|optimize|memory|leak|slow"
    )

    local lower_text
    lower_text=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    # Detect patterns
    for pattern_def in "${patterns[@]}"; do
        local name="${pattern_def%%:*}"
        local regex="${pattern_def#*:}"
        if echo "$lower_text" | grep -qiE "$regex"; then
            concepts+=("pattern:$name")
        fi
    done

    # Detect file extensions
    local files
    files=$(echo "$text" | grep -oE '[a-zA-Z0-9_/-]+\.(ts|js|tsx|jsx|py|go|rs|sh|java|rb|php)' | head -10)
    for file in $files; do
        concepts+=("file:$file")
    done

    # Detect error types
    if echo "$lower_text" | grep -qiE 'null|undefined|nil'; then
        concepts+=("error:null_reference")
    fi
    if echo "$lower_text" | grep -qiE 'type.*error|cannot.*assign|incompatible'; then
        concepts+=("error:type_error")
    fi

    # Output unique concepts
    printf '%s\n' "${concepts[@]}" | sort -u
}

# ============================================================================
# Hebbian Learning
# ============================================================================

# Update association weight between two concepts
# Usage: hebbian_update_association "concept_a" "concept_b" [activation_a] [activation_b] [context]
hebbian_update_association() {
    local concept_a="$1"
    local concept_b="$2"
    local activation_a="${3:-1.0}"
    local activation_b="${4:-1.0}"
    local context="${5:-review}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    # Don't create self-associations
    [[ "$concept_a" == "$concept_b" ]] && return 0
    [[ -z "$concept_a" || -z "$concept_b" ]] && return 1

    # Sort alphabetically to avoid duplicate pairs (a,b) and (b,a)
    if [[ "$concept_a" > "$concept_b" ]]; then
        local tmp="$concept_a"
        concept_a="$concept_b"
        concept_b="$tmp"
    fi

    local now current_weight
    now=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

    # Get current weight
    current_weight=$(sqlite3 "$db_path" \
        "SELECT weight FROM associations
         WHERE concept_a='$concept_a' AND concept_b='$concept_b'
         AND context='$context';" 2>/dev/null | tr -d '\r')
    current_weight="${current_weight:-0.5}"

    # Hebbian rule: delta_w = learning_rate * activation_a * activation_b
    local delta new_weight
    delta=$(awk -v lr="$HEBBIAN_LEARNING_RATE" -v aa="$activation_a" -v ab="$activation_b" \
        'BEGIN { printf "%.6f", lr * aa * ab }')
    new_weight=$(awk -v cw="$current_weight" -v d="$delta" \
        'BEGIN { nw = cw + d; if (nw > 1.0) nw = 1.0; printf "%.6f", nw }')

    # Upsert association
    sqlite3 "$db_path" <<SQL
INSERT INTO associations (concept_a, concept_b, weight, context, last_updated)
VALUES ('$concept_a', '$concept_b', $new_weight, '$context', '$now')
ON CONFLICT(concept_a, concept_b, context) DO UPDATE SET
    weight = $new_weight,
    co_occurrences = co_occurrences + 1,
    last_updated = '$now';
SQL

    # Update concept frequencies
    sqlite3 "$db_path" <<SQL
INSERT INTO concepts (id, type, frequency, last_seen)
VALUES ('$concept_a', '${concept_a%%:*}', 1, '$now')
ON CONFLICT(id) DO UPDATE SET frequency = frequency + 1, last_seen = '$now';

INSERT INTO concepts (id, type, frequency, last_seen)
VALUES ('$concept_b', '${concept_b%%:*}', 1, '$now')
ON CONFLICT(id) DO UPDATE SET frequency = frequency + 1, last_seen = '$now';
SQL
}

# Learn associations from a list of concepts
# Usage: hebbian_learn "concepts_string" [context]
# Input: Newline-separated list of concepts
hebbian_learn() {
    local concepts_str="$1"
    local context="${2:-review}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$concepts_str" ]] && return 0
    [[ ! -f "$db_path" ]] && return 1

    # Initialize schema if needed
    hebbian_init_schema

    local concepts=()
    while IFS= read -r concept; do
        [[ -n "$concept" ]] && concepts+=("$concept")
    done <<< "$concepts_str"

    local n=${#concepts[@]}
    [[ $n -lt 2 ]] && return 0

    # Learn all pairwise associations
    local pairs=0
    for ((i=0; i<n; i++)); do
        for ((j=i+1; j<n; j++)); do
            hebbian_update_association "${concepts[$i]}" "${concepts[$j]}" 1.0 1.0 "$context"
            ((pairs++))
        done
    done

    echo "Learned $pairs associations from $n concepts"
}

# Apply temporal decay to all weights
# Usage: hebbian_decay [days]
hebbian_decay() {
    local days="${1:-1}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && return 1

    # Calculate decay factor: rate^days
    local decay_factor
    decay_factor=$(awk -v rate="$HEBBIAN_DECAY_RATE" -v d="$days" \
        'BEGIN { printf "%.6f", rate ^ d }')

    # Apply decay
    sqlite3 "$db_path" "UPDATE associations SET weight = weight * $decay_factor;"

    # Remove weak associations below threshold
    local deleted
    deleted=$(sqlite3 "$db_path" \
        "SELECT COUNT(*) FROM associations WHERE weight < $HEBBIAN_THRESHOLD;" | tr -d '\r')
    sqlite3 "$db_path" "DELETE FROM associations WHERE weight < $HEBBIAN_THRESHOLD;"

    echo "Decay applied (factor: $decay_factor). Removed $deleted weak associations."
}

# ============================================================================
# Retrieval and Prediction
# ============================================================================

# Get related concepts for a given concept
# Usage: hebbian_get_related "concept" [limit]
# Returns: Pipe-separated "related_concept|weight"
hebbian_get_related() {
    local concept="$1"
    local limit="${2:-10}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$concept" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    sqlite3 -separator '|' "$db_path" <<SQL | tr -d '\r'
SELECT
    CASE WHEN concept_a = '$concept' THEN concept_b ELSE concept_a END as related,
    weight
FROM associations
WHERE concept_a = '$concept' OR concept_b = '$concept'
ORDER BY weight DESC
LIMIT $limit;
SQL
}

# Spread activation through the network
# Usage: hebbian_spread_activation "initial_concepts" [iterations] [decay]
# Returns: "activation|concept" sorted by activation
hebbian_spread_activation() {
    local initial_concepts="$1"
    local iterations="${2:-$HEBBIAN_SPREAD_ITERATIONS}"
    local decay="${3:-$HEBBIAN_SPREAD_DECAY}"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$initial_concepts" ]] && return 1
    [[ ! -f "$db_path" ]] && return 1

    # Use temporary file to store activations (bash associative arrays are slow)
    local tmp_file
    tmp_file=$(mktemp)
    # shellcheck disable=SC2064 # We want $tmp_file to expand now, not at signal time
    trap "rm -f '$tmp_file'" RETURN

    # Initialize activations
    while IFS= read -r concept; do
        [[ -n "$concept" ]] && echo "$concept|1.0" >> "$tmp_file"
    done <<< "$initial_concepts"

    # Spread activation for N iterations
    for ((iter=0; iter<iterations; iter++)); do
        local new_tmp
        new_tmp=$(mktemp)

        while IFS='|' read -r concept activation; do
            [[ -z "$concept" ]] && continue

            # Get neighbors and their weights
            local neighbors
            neighbors=$(sqlite3 -separator '|' "$db_path" \
                "SELECT CASE WHEN concept_a='$concept' THEN concept_b ELSE concept_a END, weight
                 FROM associations WHERE concept_a='$concept' OR concept_b='$concept';" 2>/dev/null | tr -d '\r')

            while IFS='|' read -r neighbor weight; do
                [[ -z "$neighbor" ]] && continue
                # Spread: activation * weight * decay
                local spread
                spread=$(awk -v a="$activation" -v w="$weight" -v d="$decay" \
                    'BEGIN { printf "%.6f", a * w * d }')
                echo "$neighbor|$spread" >> "$new_tmp"
            done <<< "$neighbors"

            # Keep original activation
            echo "$concept|$activation" >> "$new_tmp"
        done < "$tmp_file"

        # Merge activations for same concept
        sort -t'|' -k1,1 "$new_tmp" | awk -F'|' '
        {
            if ($1 == prev) {
                sum += $2
            } else {
                if (prev != "") print prev "|" sum
                prev = $1
                sum = $2
            }
        }
        END { if (prev != "") print prev "|" sum }
        ' > "$tmp_file"

        rm -f "$new_tmp"
    done

    # Sort by activation (descending) and output
    sort -t'|' -k2 -rn "$tmp_file" | awk -F'|' '{ printf "%.4f|%s\n", $2, $1 }'
}

# Predict issues for a file or text
# Usage: hebbian_predict "file_or_text"
hebbian_predict() {
    local input="$1"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ -z "$input" ]] && {
        echo "Usage: hebbian_predict <file_or_text>" >&2
        return 1
    }

    [[ ! -f "$db_path" ]] && {
        echo "No database found. Run reviews first to build memory." >&2
        return 1
    }

    # Check if we have associations
    local assoc_count
    assoc_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM associations;" 2>/dev/null | tr -d '\r')
    [[ -z "$assoc_count" || "$assoc_count" -lt 3 ]] && {
        echo "Insufficient memory. Need more reviews to make predictions." >&2
        return 1
    }

    # Get content (file or direct text)
    local content
    if [[ -f "$input" ]]; then
        content=$(head -100 "$input")
        echo "=== PREDICTIONS FOR: $input ==="
    else
        content="$input"
        echo "=== PREDICTIONS FOR INPUT ==="
    fi

    # Extract concepts from input
    local concepts
    concepts=$(hebbian_extract_concepts "$content")

    if [[ -z "$concepts" ]]; then
        echo "No recognizable concepts found in input."
        return 0
    fi

    echo ""
    echo "Detected concepts:"
    # shellcheck disable=SC2001 # sed is cleaner for multi-line prefix addition
    echo "$concepts" | sed 's/^/  - /'
    echo ""

    # Spread activation
    local activated
    activated=$(hebbian_spread_activation "$concepts" 2 0.6)

    if [[ -z "$activated" ]]; then
        echo "No related concepts found in memory."
        return 0
    fi

    echo "Related concepts (by association strength):"
    echo "$activated" | head -15 | while IFS='|' read -r score concept; do
        # Skip concepts already in input
        if ! echo "$concepts" | grep -qF "$concept"; then
            printf "  %.2f  %s\n" "$score" "$concept"
        fi
    done

    echo ""
    echo "Potential issues to watch for:"
    echo "$activated" | grep -E '^[0-9.]+\|(pattern:|error:)' | head -5 | while IFS='|' read -r score concept; do
        if ! echo "$concepts" | grep -qF "$concept"; then
            local name="${concept#*:}"
            printf "  - %s (confidence: %.0f%%)\n" "$name" "$(awk -v s="$score" 'BEGIN { print s * 100 }')"
        fi
    done
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if Hebbian memory is available
hebbian_check() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ "$HEBBIAN_ENABLED" != "true" ]] && {
        echo "Hebbian memory disabled (GGA_HEBBIAN_ENABLED=false)"
        return 1
    }

    [[ ! -f "$db_path" ]] && {
        echo "Database not found: $db_path"
        return 1
    }

    # Check tables exist
    local tables
    tables=$(sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('concepts', 'associations');" | tr -d '\r' | wc -l)

    if [[ "$tables" -lt 2 ]]; then
        echo "Hebbian tables not initialized. Run 'gga memory init' first."
        return 1
    fi

    local concepts associations
    concepts=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM concepts;" 2>/dev/null | tr -d '\r')
    associations=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM associations;" 2>/dev/null | tr -d '\r')

    echo "Hebbian memory available: $concepts concepts, $associations associations"
    return 0
}

# Get Hebbian memory statistics
hebbian_stats() {
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && {
        echo "No database found"
        return 1
    }

    # Check if tables exist
    local has_tables
    has_tables=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='associations';" | tr -d '\r')

    if [[ "$has_tables" -eq 0 ]]; then
        echo "Hebbian tables not initialized"
        return 1
    fi

    local concepts associations avg_weight max_weight
    concepts=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM concepts;" 2>/dev/null | tr -d '\r')
    associations=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM associations;" 2>/dev/null | tr -d '\r')
    avg_weight=$(sqlite3 "$db_path" "SELECT printf('%.4f', AVG(weight)) FROM associations;" 2>/dev/null | tr -d '\r')
    max_weight=$(sqlite3 "$db_path" "SELECT printf('%.4f', MAX(weight)) FROM associations;" 2>/dev/null | tr -d '\r')

    cat <<EOF
Hebbian Memory Stats:
  Concepts: ${concepts:-0}
  Associations: ${associations:-0}
  Average Weight: ${avg_weight:-0}
  Max Weight: ${max_weight:-0}
  Learning Rate: $HEBBIAN_LEARNING_RATE
  Decay Rate: $HEBBIAN_DECAY_RATE
  Threshold: $HEBBIAN_THRESHOLD
EOF

    if [[ "${associations:-0}" -gt 0 ]]; then
        echo ""
        echo "Top associations:"
        sqlite3 -separator ' <-> ' "$db_path" \
            "SELECT concept_a, concept_b, printf('(%.2f)', weight) FROM associations ORDER BY weight DESC LIMIT 10;" | \
            tr -d '\r' | sed 's/^/  /'
    fi
}

# Show associations for a concept or all
# Usage: hebbian_show [concept]
hebbian_show() {
    local concept="$1"
    local db_path="${GGA_DB_PATH:-$HOME/.gga/gga.db}"

    [[ ! -f "$db_path" ]] && {
        echo "No database found"
        return 1
    }

    if [[ -n "$concept" ]]; then
        echo "Associations for: $concept"
        hebbian_get_related "$concept" 20 | while IFS='|' read -r related weight; do
            printf "  %.4f  %s\n" "$weight" "$related"
        done
    else
        echo "All associations (top 50):"
        sqlite3 -separator '|' "$db_path" \
            "SELECT concept_a, concept_b, weight FROM associations ORDER BY weight DESC LIMIT 50;" | \
            tr -d '\r' | while IFS='|' read -r a b w; do
            printf "  %.4f  %s <-> %s\n" "$w" "$a" "$b"
        done
    fi
}

# Learn from a completed review
# Usage: hebbian_learn_from_review "files" "diff_content" "result" "status"
hebbian_learn_from_review() {
    local files="$1"
    local diff_content="$2"
    local result="$3"
    local status="$4"

    [[ "$HEBBIAN_ENABLED" != "true" ]] && return 0

    # Combine all text for concept extraction
    local all_text="$files $diff_content $result"

    # Extract concepts
    local concepts
    concepts=$(hebbian_extract_concepts "$all_text")

    # Add status as a concept
    [[ -n "$status" ]] && concepts+=$'\n'"status:$status"

    # Learn associations
    if [[ -n "$concepts" ]]; then
        hebbian_learn "$concepts" "review" >/dev/null 2>&1
    fi
}
