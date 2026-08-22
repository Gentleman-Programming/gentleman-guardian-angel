# shellcheck shell=bash

Describe 'File size detection'
  setup() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'check_file_sizes()'
    # Mirror the implementation from bin/gga
    check_file_sizes() {
      local files="$1"
      local max_size="$2"
      local use_staged="${3:-false}"

      if [[ -z "$max_size" || "$max_size" == "0" ]]; then
        return
      fi

      while IFS= read -r file; do
        if [[ -z "$file" ]]; then
          continue
        fi

        local file_size
        if [[ "$use_staged" == "true" ]]; then
          file_size=$(git show ":$file" 2>/dev/null | wc -c)
        else
          if [[ -f "$file" ]]; then
            file_size=$(wc -c < "$file")
          else
            file_size=0
          fi
        fi

        if [[ "$file_size" -gt "$max_size" ]]; then
          echo "$file:$file_size"
        fi
      done <<< "$files"
    }

    It 'returns empty when all files are under limit'
      echo "small content" > small.ts
      git add small.ts

      result=$(check_file_sizes "small.ts" "1000" "false")

      The value "$result" should equal ""
    End

    It 'detects files exceeding limit'
      # Create a file larger than 100 bytes
      dd if=/dev/zero of=large.ts bs=200 count=1 2>/dev/null
      git add large.ts

      result=$(check_file_sizes "large.ts" "100" "false")

      The value "$result" should include "large.ts"
    End

    It 'returns file with size in output'
      dd if=/dev/zero of=large.ts bs=200 count=1 2>/dev/null
      git add large.ts

      result=$(check_file_sizes "large.ts" "100" "false")

      The value "$result" should include ":"
    End

    It 'returns empty when limit is 0 (no limit)'
      dd if=/dev/zero of=large.ts bs=1000 count=1 2>/dev/null
      git add large.ts

      result=$(check_file_sizes "large.ts" "0" "false")

      The value "$result" should equal ""
    End

    It 'returns empty when limit is empty (no limit)'
      dd if=/dev/zero of=large.ts bs=1000 count=1 2>/dev/null
      git add large.ts

      result=$(check_file_sizes "large.ts" "" "false")

      The value "$result" should equal ""
    End

    It 'checks multiple files and returns only large ones'
      echo "small" > small.ts
      dd if=/dev/zero of=large.ts bs=200 count=1 2>/dev/null
      echo "also small" > another.ts
      git add small.ts large.ts another.ts

      files=$'small.ts\nlarge.ts\nanother.ts'
      result=$(check_file_sizes "$files" "100" "false")

      The value "$result" should include "large.ts"
      The value "$result" should not include "small.ts"
      The value "$result" should not include "another.ts"
    End

    It 'checks staged content size when use_staged is true'
      # Create a small file, stage it, then make it large in working dir
      echo "small staged content" > file.ts
      git add file.ts
      dd if=/dev/zero of=file.ts bs=1000 count=1 2>/dev/null

      result=$(check_file_sizes "file.ts" "100" "true")

      # Staged content is small, so should not exceed limit
      The value "$result" should equal ""
    End

    It 'detects large staged content'
      # Create a large file and stage it
      dd if=/dev/zero of=file.ts bs=200 count=1 2>/dev/null
      git add file.ts

      result=$(check_file_sizes "file.ts" "100" "true")

      The value "$result" should include "file.ts"
    End
  End

  Describe 'format_file_size()'
    # Mirror the implementation from bin/gga
    format_file_size() {
      local bytes="$1"
      if [[ "$bytes" -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
      elif [[ "$bytes" -ge 1024 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")KB"
      else
        echo "${bytes}B"
      fi
    }

    It 'formats bytes correctly'
      result=$(format_file_size "500")
      The value "$result" should equal "500B"
    End

    It 'formats kilobytes correctly'
      result=$(format_file_size "2048")
      The value "$result" should equal "2.0KB"
    End

    It 'formats megabytes correctly'
      result=$(format_file_size "2097152")
      The value "$result" should equal "2.0MB"
    End

    It 'formats 100KB correctly'
      result=$(format_file_size "100000")
      The value "$result" should equal "97.7KB"
    End
  End
End