# shellcheck shell=bash
# ============================================================================
# Persistence helpers – high-level functions that orchestrate SQLite storage
# ============================================================================

# Source guard
[[ -n "${_PERSISTENCE_LOADED:-}" ]] && return 0
_PERSISTENCE_LOADED=1

# Save review result to SQLite database
# Usage: save_review_to_db <status> <files_to_review> <result> <provider> <duration_ms>
save_review_to_db() {
  local review_status="$1"
  local files_to_review="$2"
  local result="$3"
  local provider="$4"
  local duration_ms="${5:-0}"

  # Only save if sqlite3 is available
  command -v sqlite3 &> /dev/null || return 0

  # Initialize database if needed (failures should not block review execution)
  load_env_config > /dev/null 2>&1 || return 0
  db_init > /dev/null 2>&1 || return 0

  # Get project info
  local project_path project_name git_branch git_commit
  project_path=$(pwd)
  project_name=$(basename "$project_path")
  git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")

  # Build files list and count
  local files_list files_count
  files_list=$(echo "$files_to_review" | tr '\n' ',' | sed 's/,$//')
  files_count=$(echo "$files_to_review" | awk 'NF{c++} END{print c+0}')

  # Generate diff hash for deduplication
  local diff_content diff_hash
  diff_content=$(git diff --cached 2>/dev/null || echo "")
  if [[ -n "$diff_content" ]]; then
    diff_hash=$(echo "$diff_content" | _compute_hash_stdin 2>/dev/null || echo "")
  else
    # Empty diff: generate unique hash to avoid collision (all empty diffs
    # would otherwise share the same hash, causing silent upsert overwrites)
    diff_hash=$(echo "empty-${project_path}-${git_branch}-${git_commit}-$(date +%s%3N 2>/dev/null || date +%s)-$$" \
      | _compute_hash_stdin 2>/dev/null || echo "")
  fi

  # Save to database
  db_save_review "$project_path" "$project_name" "$git_branch" "$git_commit" \
    "$files_list" "$files_count" "$diff_content" "$diff_hash" \
    "$result" "$review_status" "$provider" "" "$duration_ms" 2>/dev/null || true

  # Extract structured insights from review result
  local review_id
  review_id=$(sqlite3 "$GGA_DB_PATH" \
    "SELECT id FROM reviews WHERE diff_hash = '$diff_hash' LIMIT 1;" 2>/dev/null | tr -d '\r') || true
  if [[ -n "$review_id" ]]; then
    extract_review_insights "$review_id" "$result" "$files_to_review" 2>/dev/null || true

    # Send insights to Engram if enabled
    if [[ "${GGA_ENGRAM_ENABLED:-false}" == "true" ]]; then
      engram_save_observation \
        "Review $review_status: $files_count file(s) in $project_name" \
        "review" \
        "Status: $review_status | Files: $files_list | Provider: $provider" \
        "$project_name" 2>/dev/null || true
    fi
  fi
}
