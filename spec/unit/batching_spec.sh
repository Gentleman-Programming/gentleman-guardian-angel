# shellcheck shell=bash

Describe 'Prompt batching functionality'
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

  # Mirror the implementations from bin/gga
  calculate_file_content_size() {
    local file="$1"
    local use_staged="${2:-false}"

    if [[ -z "$file" ]]; then
      echo "0"
      return
    fi

    local size
    if [[ "$use_staged" == "true" ]]; then
      size=$(git show ":$file" 2>/dev/null | wc -c)
    else
      if [[ -f "$file" ]]; then
        size=$(wc -c < "$file")
      else
        size=0
      fi
    fi

    echo "$size"
  }

  calculate_prompt_overhead() {
    local rules="$1"
    local rules_size=${#rules}
    local base_overhead=700
    echo $((base_overhead + rules_size))
  }

  calculate_prompt_size_for_files() {
    local files="$1"
    local use_staged="${2:-false}"
    local rules="${3:-}"

    local total_size=0
    total_size=$(calculate_prompt_overhead "$rules")

    while IFS= read -r file; do
      if [[ -n "$file" ]]; then
        local file_size
        file_size=$(calculate_file_content_size "$file" "$use_staged")
        total_size=$((total_size + file_size + 30 + ${#file}))
      fi
    done <<< "$files"

    echo "$total_size"
  }

  split_files_into_batches() {
    local files="$1"
    local max_size="${2:-0}"
    local use_staged="${3:-false}"
    local rules="${4:-}"

    if [[ -z "$max_size" || "$max_size" == "0" ]]; then
      echo "$files"
      return
    fi

    local overhead
    overhead=$(calculate_prompt_overhead "$rules")

    local available_space=$((max_size - overhead))

    if [[ $available_space -le 0 ]]; then
      echo "$files"
      return
    fi

    local current_batch=""
    local current_batch_size=0
    local batch_count=0

    while IFS= read -r file; do
      if [[ -z "$file" ]]; then
        continue
      fi

      local file_size
      file_size=$(calculate_file_content_size "$file" "$use_staged")
      local file_overhead=$((30 + ${#file}))
      local total_file_size=$((file_size + file_overhead))

      if [[ $current_batch_size -gt 0 && $((current_batch_size + total_file_size)) -gt $available_space ]]; then
        if [[ $batch_count -gt 0 ]]; then
          echo ""
          echo "---BATCH---"
        fi
        printf '%s' "$current_batch"
        batch_count=$((batch_count + 1))
        current_batch=""
        current_batch_size=0
      fi

      if [[ -n "$current_batch" ]]; then
        current_batch="$current_batch"$'\n'"$file"
      else
        current_batch="$file"
      fi
      current_batch_size=$((current_batch_size + total_file_size))
    done <<< "$files"

    if [[ -n "$current_batch" ]]; then
      if [[ $batch_count -gt 0 ]]; then
        echo ""
        echo "---BATCH---"
      fi
      printf '%s\n' "$current_batch"
    fi
  }

  count_batches() {
    local batch_output="$1"

    if [[ -z "$batch_output" ]]; then
      echo "0"
      return
    fi

    local count
    count=$(echo "$batch_output" | grep -c "^---BATCH---$" || true)
    echo $((count + 1))
  }

  get_batch() {
    local batch_output="$1"
    local batch_num="$2"

    if [[ -z "$batch_output" || -z "$batch_num" ]]; then
      return
    fi

    local current_batch=0
    local in_target_batch=false
    local result=""

    while IFS= read -r line; do
      if [[ "$line" == "---BATCH---" ]]; then
        current_batch=$((current_batch + 1))
        if [[ "$in_target_batch" == true ]]; then
          break
        fi
        if [[ $current_batch -eq $((batch_num - 1)) ]]; then
          in_target_batch=true
        fi
        continue
      fi

      if [[ $current_batch -eq 0 && $batch_num -eq 1 ]]; then
        if [[ -n "$line" ]]; then
          if [[ -n "$result" ]]; then
            result="$result"$'\n'"$line"
          else
            result="$line"
          fi
        fi
      elif [[ "$in_target_batch" == true ]]; then
        if [[ -n "$line" ]]; then
          if [[ -n "$result" ]]; then
            result="$result"$'\n'"$line"
          else
            result="$line"
          fi
        fi
      fi
    done <<< "$batch_output"

    echo "$result"
  }

  Describe 'calculate_file_content_size()'
    It 'returns 0 for empty input'
      result=$(calculate_file_content_size "")
      The value "$result" should equal "0"
    End

    It 'returns correct size for a file'
      echo "hello world" > test.txt
      result=$(calculate_file_content_size "test.txt" "false")
      # "hello world\n" = 12 bytes
      The value "$result" should equal "12"
    End

    It 'returns size of staged content'
      echo "staged content" > test.txt
      git add test.txt
      echo "modified content that is longer" > test.txt
      result=$(calculate_file_content_size "test.txt" "true")
      # "staged content\n" = 15 bytes
      The value "$result" should equal "15"
    End
  End

  Describe 'calculate_prompt_overhead()'
    It 'returns base overhead for empty rules'
      result=$(calculate_prompt_overhead "")
      The value "$result" should equal "700"
    End

    It 'adds rules size to overhead'
      rules="# Some rules here"
      result=$(calculate_prompt_overhead "$rules")
      expected=$((700 + ${#rules}))
      The value "$result" should equal "$expected"
    End
  End

  Describe 'calculate_prompt_size_for_files()'
    It 'calculates size for a single file'
      echo "content" > file.txt
      git add file.txt
      result=$(calculate_prompt_size_for_files "file.txt" "false" "")
      # overhead (700) + file content (8) + file header overhead (~30 + filename length)
      # Should be > 700
      The value "$((result > 700))" should equal "1"
    End

    It 'calculates size for multiple files'
      echo "content1" > file1.txt
      echo "content2" > file2.txt
      files=$'file1.txt\nfile2.txt'
      result=$(calculate_prompt_size_for_files "$files" "false" "")
      # Should be larger than single file
      single=$(calculate_prompt_size_for_files "file1.txt" "false" "")
      The value "$((result > single))" should equal "1"
    End
  End

  Describe 'split_files_into_batches()'
    It 'returns all files when max_size is 0'
      echo "content" > file1.txt
      echo "content" > file2.txt
      files=$'file1.txt\nfile2.txt'

      result=$(split_files_into_batches "$files" "0" "false" "")

      The value "$result" should include "file1.txt"
      The value "$result" should include "file2.txt"
      The value "$result" should not include "---BATCH---"
    End

    It 'returns all files when max_size is empty'
      echo "content" > file1.txt
      files="file1.txt"

      result=$(split_files_into_batches "$files" "" "false" "")

      The value "$result" should include "file1.txt"
    End

    It 'splits files into batches when exceeding max_size'
      # Create files with known sizes
      dd if=/dev/zero of=large1.txt bs=500 count=1 2>/dev/null
      dd if=/dev/zero of=large2.txt bs=500 count=1 2>/dev/null
      dd if=/dev/zero of=large3.txt bs=500 count=1 2>/dev/null
      files=$'large1.txt\nlarge2.txt\nlarge3.txt'

      # Set max_size to allow ~2 files per batch (700 overhead + ~1000 for files)
      result=$(split_files_into_batches "$files" "1300" "false" "")

      The value "$result" should include "---BATCH---"
    End

    It 'keeps small files in single batch'
      echo "a" > small1.txt
      echo "b" > small2.txt
      echo "c" > small3.txt
      files=$'small1.txt\nsmall2.txt\nsmall3.txt'

      # Large enough to fit all
      result=$(split_files_into_batches "$files" "50000" "false" "")

      The value "$result" should not include "---BATCH---"
      The value "$result" should include "small1.txt"
      The value "$result" should include "small2.txt"
      The value "$result" should include "small3.txt"
    End
  End

  Describe 'count_batches()'
    It 'returns 0 for empty input'
      result=$(count_batches "")
      The value "$result" should equal "0"
    End

    It 'returns 1 for single batch (no separator)'
      batch_output=$'file1.txt\nfile2.txt'
      result=$(count_batches "$batch_output")
      The value "$result" should equal "1"
    End

    It 'returns correct count for multiple batches'
      batch_output=$'file1.txt\n---BATCH---\nfile2.txt\n---BATCH---\nfile3.txt'
      result=$(count_batches "$batch_output")
      The value "$result" should equal "3"
    End
  End

  Describe 'get_batch()'
    It 'returns first batch correctly'
      batch_output=$'file1.txt\nfile2.txt\n---BATCH---\nfile3.txt'
      result=$(get_batch "$batch_output" "1")
      The value "$result" should include "file1.txt"
      The value "$result" should include "file2.txt"
      The value "$result" should not include "file3.txt"
    End

    It 'returns second batch correctly'
      batch_output=$'file1.txt\n---BATCH---\nfile2.txt\nfile3.txt'
      result=$(get_batch "$batch_output" "2")
      The value "$result" should include "file2.txt"
      The value "$result" should include "file3.txt"
      The value "$result" should not include "file1.txt"
    End

    It 'returns empty for invalid batch number'
      batch_output=$'file1.txt'
      result=$(get_batch "$batch_output" "5")
      The value "$result" should equal ""
    End
  End

  Describe 'Integration: batching workflow'
    It 'correctly splits and retrieves all files'
      # Create files with significant sizes to force batching
      dd if=/dev/zero of=file1.txt bs=1000 count=1 2>/dev/null
      dd if=/dev/zero of=file2.txt bs=1000 count=1 2>/dev/null
      dd if=/dev/zero of=file3.txt bs=1000 count=1 2>/dev/null
      files=$'file1.txt\nfile2.txt\nfile3.txt'

      # Split into batches (max_size = 1800)
      # overhead ~700 + each file ~1030 bytes = ~1730 for one file
      # Adding second file would exceed 1800, so should split
      batch_output=$(split_files_into_batches "$files" "1800" "false" "")
      num_batches=$(count_batches "$batch_output")

      # Should have multiple batches (at least 2)
      The value "$((num_batches >= 2))" should equal "1"

      # Verify all files are present across batches
      all_files=""
      batch_num=1
      while [[ $batch_num -le $num_batches ]]; do
        batch_files=$(get_batch "$batch_output" "$batch_num")
        if [[ -n "$all_files" ]]; then
          all_files="$all_files"$'\n'"$batch_files"
        else
          all_files="$batch_files"
        fi
        batch_num=$((batch_num + 1))
      done

      The value "$all_files" should include "file1.txt"
      The value "$all_files" should include "file2.txt"
      The value "$all_files" should include "file3.txt"
    End
  End
End
Describe 'renumber_findings()'
  renumber_findings() {
    local findings="$1"
    local n=1

    while IFS= read -r finding; do
      if [[ -n "$finding" ]]; then
        printf '#%s %s\n' "$n" "$(printf '%s' "$finding" | sed 's/^#[0-9]*[[:space:]]*//')"
        n=$((n + 1))
      fi
    done <<< "$findings"
  }

  It 'renumbers sequentially across batches that each restart at #1'
    findings="#1 a.ts:10 - rule - first
#2 b.ts:20 - rule - second
#1 c.ts:30 - rule - third"

    When call renumber_findings "$findings"
    The line 1 should equal "#1 a.ts:10 - rule - first"
    The line 2 should equal "#2 b.ts:20 - rule - second"
    The line 3 should equal "#3 c.ts:30 - rule - third"
  End

  It 'skips blank lines'
    findings="#1 a.ts:1 - rule - one

#1 b.ts:2 - rule - two"

    When call renumber_findings "$findings"
    The line 1 should equal "#1 a.ts:1 - rule - one"
    The line 2 should equal "#2 b.ts:2 - rule - two"
  End

  It 'returns nothing for empty input'
    When call renumber_findings ""
    The output should equal ""
  End
End
