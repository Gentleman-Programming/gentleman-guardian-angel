# shellcheck shell=bash

Describe 'cache.sh'
  Include "$LIB_DIR/cache.sh"

  Describe 'get_file_hash()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      echo "test content" > "$TEMP_DIR/test.txt"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns a 64 character SHA256 hash'
      When call get_file_hash "$TEMP_DIR/test.txt"
      The status should be success
      The length of output should eq 64
    End

    It 'returns empty for non-existent file'
      When call get_file_hash "$TEMP_DIR/nonexistent.txt"
      The output should eq ""
    End

    It 'returns different hashes for different content'
      echo "different content" > "$TEMP_DIR/other.txt"
      hash1=$(get_file_hash "$TEMP_DIR/test.txt")
      hash2=$(get_file_hash "$TEMP_DIR/other.txt")
      The value "$hash1" should not eq "$hash2"
    End

    It 'returns same hash for same content'
      echo "test content" > "$TEMP_DIR/copy.txt"
      hash1=$(get_file_hash "$TEMP_DIR/test.txt")
      hash2=$(get_file_hash "$TEMP_DIR/copy.txt")
      The value "$hash1" should eq "$hash2"
    End
  End

  Describe 'get_string_hash()'
    It 'returns a 64 character SHA256 hash'
      When call get_string_hash "test string"
      The status should be success
      The length of output should eq 64
    End

    It 'returns different hashes for different strings'
      hash1=$(get_string_hash "string1")
      hash2=$(get_string_hash "string2")
      The value "$hash1" should not eq "$hash2"
    End

    It 'returns same hash for same string'
      hash1=$(get_string_hash "same")
      hash2=$(get_string_hash "same")
      The value "$hash1" should eq "$hash2"
    End
  End

  Describe 'get_project_id()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns a hash for a git repository'
      When call get_project_id
      The status should be success
      The length of output should eq 64
    End

    It 'returns consistent hash for same repo'
      hash1=$(get_project_id)
      hash2=$(get_project_id)
      The value "$hash1" should eq "$hash2"
    End
  End

  Describe 'get_metadata_hash()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      echo "rules content" > "$TEMP_DIR/AGENTS.md"
      echo "config content" > "$TEMP_DIR/.gga"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns a hash combining rules and config'
      When call get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga"
      The status should be success
      The length of output should eq 64
    End

    It 'changes when rules file changes'
      hash1=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      echo "new rules" > "$TEMP_DIR/AGENTS.md"
      hash2=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      The value "$hash1" should not eq "$hash2"
    End

    It 'changes when config file changes'
      hash1=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      echo "new config" > "$TEMP_DIR/.gga"
      hash2=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      The value "$hash1" should not eq "$hash2"
    End
  End

  Describe 'init_cache()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo "config" > .gga
      # Override cache dir for testing
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates cache directory structure'
      When call init_cache "AGENTS.md" ".gga"
      The status should be success
      The output should be present
      The path "$CACHE_DIR" should be directory
    End

    It 'creates metadata file'
      init_cache "AGENTS.md" ".gga" > /dev/null
      cache_dir=$(get_project_cache_dir)
      The path "$cache_dir/metadata" should be file
    End

    It 'creates files subdirectory'
      init_cache "AGENTS.md" ".gga" > /dev/null
      cache_dir=$(get_project_cache_dir)
      The path "$cache_dir/files" should be directory
    End
  End

  Describe 'is_cache_valid()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo "config" > .gga
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      init_cache "AGENTS.md" ".gga" > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns success when cache is valid'
      When call is_cache_valid "AGENTS.md" ".gga"
      The status should be success
    End

    It 'returns failure when rules change'
      echo "new rules" > AGENTS.md
      When call is_cache_valid "AGENTS.md" ".gga"
      The status should be failure
    End

    It 'returns failure when config changes'
      echo "new config" > .gga
      When call is_cache_valid "AGENTS.md" ".gga"
      The status should be failure
    End
  End

  Describe 'cache_file_result() and is_file_cached()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo "config" > .gga
      echo "file content" > test.ts
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      init_cache "AGENTS.md" ".gga" > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'caches a file with PASSED status'
      When call cache_file_result "test.ts" "PASSED"
      The status should be success
    End

    It 'detects cached file'
      cache_file_result "test.ts" "PASSED"
      When call is_file_cached "test.ts"
      The status should be success
    End

    It 'does not detect uncached file'
      When call is_file_cached "uncached.ts"
      The status should be failure
    End

    It 'invalidates cache when file content changes'
      cache_file_result "test.ts" "PASSED"
      echo "new content" > test.ts
      When call is_file_cached "test.ts"
      The status should be failure
    End
  End

  Describe 'filter_uncached_files()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo "config" > .gga
      echo "content1" > file1.ts
      echo "content2" > file2.ts
      echo "content3" > file3.ts
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      init_cache "AGENTS.md" ".gga" > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns all files when none are cached'
      files=$'file1.ts\nfile2.ts\nfile3.ts'
      When call filter_uncached_files "$files"
      The output should include "file1.ts"
      The output should include "file2.ts"
      The output should include "file3.ts"
    End

    It 'filters out cached files'
      cache_file_result "file1.ts" "PASSED"
      cache_file_result "file2.ts" "PASSED"
      files=$'file1.ts\nfile2.ts\nfile3.ts'
      When call filter_uncached_files "$files"
      The output should not include "file1.ts"
      The output should not include "file2.ts"
      The output should include "file3.ts"
    End

    It 'returns empty when all files are cached'
      cache_file_result "file1.ts" "PASSED"
      cache_file_result "file2.ts" "PASSED"
      cache_file_result "file3.ts" "PASSED"
      files=$'file1.ts\nfile2.ts\nfile3.ts'
      When call filter_uncached_files "$files"
      The output should eq ""
    End
  End

  Describe 'get_staged_file_hash()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
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

    It 'returns a 64 character SHA256 hash for a staged file'
      echo "staged content" > test.txt
      git add test.txt
      When call get_staged_file_hash "test.txt"
      The status should be success
      The length of output should eq 64
    End

    It 'returns empty for a file not in the index'
      When call get_staged_file_hash "nonexistent.txt"
      The output should eq ""
      The status should be failure
    End

    It 'returns hash of staged content, not working directory content'
      echo "staged version" > test.txt
      git add test.txt
      echo "working dir version" > test.txt

      staged_hash=$(get_staged_file_hash "test.txt")
      working_hash=$(get_file_hash "test.txt")

      The value "$staged_hash" should not eq "$working_hash"
    End

    It 'returns same hash for same staged content'
      echo "same content" > file1.txt
      echo "same content" > file2.txt
      git add file1.txt file2.txt

      hash1=$(get_staged_file_hash "file1.txt")
      hash2=$(get_staged_file_hash "file2.txt")

      The value "$hash1" should eq "$hash2"
    End

    It 'works when file is deleted from working directory after staging'
      echo "will be deleted" > test.txt
      git add test.txt
      rm test.txt

      When call get_staged_file_hash "test.txt"
      The status should be success
      The length of output should eq 64
    End
  End

  Describe 'cache with use_staged parameter'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      git config user.email "test@test.com"
      git config user.name "Test User"
      echo "rules" > AGENTS.md
      echo "config" > .gga
      echo "staged content" > test.ts
      git add test.ts
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      init_cache "AGENTS.md" ".gga" > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'caches using staged hash when use_staged is true'
      cache_file_result "test.ts" "PASSED" "true"
      When call is_file_cached "test.ts" "true"
      The status should be success
    End

    It 'cache hit on staged hash even when working dir differs'
      cache_file_result "test.ts" "PASSED" "true"
      echo "modified working content" > test.ts
      When call is_file_cached "test.ts" "true"
      The status should be success
    End

    It 'cache miss when using working dir hash but cached with staged hash'
      cache_file_result "test.ts" "PASSED" "true"
      echo "different content" > test.ts
      When call is_file_cached "test.ts" "false"
      The status should be failure
    End

    It 'cache miss when staged content changes'
      cache_file_result "test.ts" "PASSED" "true"
      echo "new staged content" > test.ts
      git add test.ts
      When call is_file_cached "test.ts" "true"
      The status should be failure
    End

    It 'defaults to working directory hash when use_staged not specified'
      cache_file_result "test.ts" "PASSED"
      When call is_file_cached "test.ts"
      The status should be success
    End

    It 'filter_uncached_files works with use_staged parameter'
      cache_file_result "test.ts" "PASSED" "true"
      echo "content2" > file2.ts
      git add file2.ts
      files=$'test.ts\nfile2.ts'
      When call filter_uncached_files "$files" "true"
      The output should not include "test.ts"
      The output should include "file2.ts"
    End
  End

  Describe 'clear_project_cache()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo "config" > .gga
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      init_cache "AGENTS.md" ".gga" > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'removes project cache directory'
      cache_dir=$(get_project_cache_dir)
      clear_project_cache
      The path "$cache_dir" should not be exist
    End
  End

  Describe 'clear_all_cache()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export CACHE_DIR="$TEMP_DIR/.cache/gga"
      mkdir -p "$CACHE_DIR/project1"
      mkdir -p "$CACHE_DIR/project2"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'removes entire cache directory'
      clear_all_cache
      The path "$CACHE_DIR" should not be exist
    End
  End
End
