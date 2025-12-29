#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Cache Functions
# ============================================================================
# Intelligent caching to avoid re-reviewing unchanged files.
# Cache invalidates when:
#   - File content changes (hash)
#   - Any rules file changes (supports multiple files via RULES_FILES)
#   - Config file (.gga) changes
# ============================================================================

CACHE_DIR="$HOME/.cache/gga"

# ============================================================================
# Cache Functions
# ============================================================================

# Get hash of a file's content
get_file_hash() {
  local file="$1"
  if [[ -f "$file" ]]; then
    shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1
  else
    echo ""
  fi
}

# Get hash of a string
get_string_hash() {
  local str="$1"
  echo -n "$str" | shasum -a 256 | cut -d' ' -f1
}

# Get project identifier (based on git root path)
get_project_id() {
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$git_root" ]]; then
    get_string_hash "$git_root"
  else
    echo ""
  fi
}

# Get metadata hash (rules files + config combined)
# Supports multiple rules files via comma-separated RULES_FILES
get_metadata_hash() {
  local rules_files="$1"  # Comma-separated list of rules files
  local config_file="$2"
  
  local combined_rules_hash=""
  local config_hash=""
  
  # Hash each rules file and combine
  IFS=',' read -ra files_array <<< "$rules_files"
  for file in "${files_array[@]}"; do
    file=$(echo "$file" | xargs)  # Trim whitespace
    if [[ -n "$file" && -f "$file" ]]; then
      local file_hash
      file_hash=$(get_file_hash "$file")
      combined_rules_hash="${combined_rules_hash}:${file_hash}"
    fi
  done
  
  if [[ -f "$config_file" ]]; then
    config_hash=$(get_file_hash "$config_file")
  fi
  
  get_string_hash "${combined_rules_hash}:${config_hash}"
}

# Get project cache directory
get_project_cache_dir() {
  local project_id
  project_id=$(get_project_id)
  
  if [[ -z "$project_id" ]]; then
    echo ""
    return 1
  fi
  
  echo "$CACHE_DIR/$project_id"
}

# Initialize cache for project
init_cache() {
  local rules_file="$1"
  local config_file="$2"
  
  local cache_dir
  cache_dir=$(get_project_cache_dir)
  
  if [[ -z "$cache_dir" ]]; then
    return 1
  fi
  
  # Create cache directories
  mkdir -p "$cache_dir/files"
  
  # Store metadata hash
  local metadata_hash
  metadata_hash=$(get_metadata_hash "$rules_file" "$config_file")
  echo "$metadata_hash" > "$cache_dir/metadata"
  
  echo "$cache_dir"
}

# Check if cache is valid (metadata hasn't changed)
is_cache_valid() {
  local rules_file="$1"
  local config_file="$2"
  
  local cache_dir
  cache_dir=$(get_project_cache_dir)
  
  if [[ -z "$cache_dir" || ! -d "$cache_dir" ]]; then
    return 1
  fi
  
  # Check if metadata file exists
  if [[ ! -f "$cache_dir/metadata" ]]; then
    return 1
  fi
  
  # Compare metadata hashes
  local stored_hash
  local current_hash
  stored_hash=$(cat "$cache_dir/metadata")
  current_hash=$(get_metadata_hash "$rules_file" "$config_file")
  
  if [[ "$stored_hash" == "$current_hash" ]]; then
    return 0
  else
    return 1
  fi
}

# Invalidate entire project cache
invalidate_cache() {
  local cache_dir
  cache_dir=$(get_project_cache_dir)
  
  if [[ -n "$cache_dir" && -d "$cache_dir" ]]; then
    rm -rf "$cache_dir"
  fi
}

# Check if a file is cached (and cache is still valid for that file)
is_file_cached() {
  local file="$1"
  
  local cache_dir
  cache_dir=$(get_project_cache_dir)
  
  if [[ -z "$cache_dir" || ! -d "$cache_dir/files" ]]; then
    return 1
  fi
  
  # Get current file hash
  local file_hash
  file_hash=$(get_file_hash "$file")
  
  if [[ -z "$file_hash" ]]; then
    return 1
  fi
  
  # Check if cached file exists with this hash
  local cache_file="$cache_dir/files/$file_hash"
  
  if [[ -f "$cache_file" ]]; then
    # Verify the cached status is PASSED
    local cached_status
    cached_status=$(cat "$cache_file")
    if [[ "$cached_status" == "PASSED" ]]; then
      return 0
    fi
  fi
  
  return 1
}

# Cache a file's review result
cache_file_result() {
  local file="$1"
  local status="$2"  # PASSED or FAILED
  
  local cache_dir
  cache_dir=$(get_project_cache_dir)
  
  if [[ -z "$cache_dir" ]]; then
    return 1
  fi
  
  mkdir -p "$cache_dir/files"
  
  # Get file hash
  local file_hash
  file_hash=$(get_file_hash "$file")
  
  if [[ -n "$file_hash" ]]; then
    echo "$status" > "$cache_dir/files/$file_hash"
  fi
}

# Cache multiple files as passed
cache_files_passed() {
  local files="$1"
  
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      cache_file_result "$file" "PASSED"
    fi
  done <<< "$files"
}

# Filter out cached files from list
filter_uncached_files() {
  local files="$1"
  local uncached=""
  
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      if ! is_file_cached "$file"; then
        if [[ -n "$uncached" ]]; then
          uncached="$uncached"$'\n'"$file"
        else
          uncached="$file"
        fi
      fi
    fi
  done <<< "$files"
  
  echo "$uncached"
}

# Get cache stats for display
get_cache_stats() {
  local files="$1"
  local total=0
  local cached=0
  
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      ((total++))
      if is_file_cached "$file"; then
        ((cached++))
      fi
    fi
  done <<< "$files"
  
  echo "$cached/$total"
}

# Clear all cache
clear_all_cache() {
  if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
  fi
}

# Clear project cache
clear_project_cache() {
  invalidate_cache
}
