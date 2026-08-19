# shellcheck shell=bash

Describe 'Binary file detection'
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

  Describe 'get_binary_staged_files()'
    # Mirror the implementation from bin/gga
    get_binary_staged_files() {
      while IFS=$'\t' read -r added deleted file; do
        if [[ "$added" == "-" && "$deleted" == "-" ]]; then
          echo "$file"
        fi
      done < <(git diff --cached --numstat --diff-filter=ACM 2>/dev/null)
    }

    It 'returns empty for text files only'
      echo "const x = 1;" > file.ts
      git add file.ts

      result=$(get_binary_staged_files)

      The value "$result" should equal ""
    End

    It 'detects binary files'
      # Use printf with null byte to ensure git detects as binary
      printf '\x00binary content' > binary.bin
      git add binary.bin

      result=$(get_binary_staged_files)

      The value "$result" should equal "binary.bin"
    End

    It 'returns multiple binary files'
      # Use printf with null bytes to ensure git detects as binary
      printf '\x00\x01\x02\x03' > file1.bin
      printf '\x00\x04\x05\x06' > file2.bin
      git add file1.bin file2.bin

      result=$(get_binary_staged_files)

      The value "$result" should include "file1.bin"
      The value "$result" should include "file2.bin"
    End

    It 'only returns binary files when mixed with text'
      echo "text content" > text.ts
      # Use printf with null byte to ensure git detects as binary
      printf '\x00image data' > image.bin
      git add text.ts image.bin

      result=$(get_binary_staged_files)

      The value "$result" should equal "image.bin"
    End
  End

  Describe 'filter_binary_files()'
    filter_binary_files() {
      local files="$1"
      local binaries="$2"

      if [[ -z "$binaries" ]]; then
        echo "$files"
        return
      fi

      echo "$files" | while IFS= read -r file; do
        if [[ -n "$file" ]] && ! echo "$binaries" | grep -qxF "$file"; then
          echo "$file"
        fi
      done
    }

    It 'returns all files when no binaries'
      files=$'file1.ts\nfile2.ts'
      binaries=""

      result=$(filter_binary_files "$files" "$binaries")

      The value "$result" should include "file1.ts"
      The value "$result" should include "file2.ts"
    End

    It 'removes binary files from list'
      files=$'file.ts\nbinary.bin\nother.ts'
      binaries="binary.bin"

      result=$(filter_binary_files "$files" "$binaries")

      The value "$result" should include "file.ts"
      The value "$result" should include "other.ts"
      The value "$result" should not include "binary.bin"
    End

    It 'removes multiple binary files'
      files=$'file.ts\nimage.png\ndata.bin\nother.ts'
      binaries=$'image.png\ndata.bin'

      result=$(filter_binary_files "$files" "$binaries")

      The value "$result" should include "file.ts"
      The value "$result" should include "other.ts"
      The value "$result" should not include "image.png"
      The value "$result" should not include "data.bin"
    End

    It 'returns empty when all files are binary'
      files=$'binary1.bin\nbinary2.bin'
      binaries=$'binary1.bin\nbinary2.bin'

      result=$(filter_binary_files "$files" "$binaries")

      The value "$result" should equal ""
    End
  End
End
