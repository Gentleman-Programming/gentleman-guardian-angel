# shellcheck shell=bash

# ============================================================================
# Tests for execute_with_timeout() and execute_provider_with_timeout()
# ============================================================================
# TDD: Tests written BEFORE implementation.
# Based on the design from PR #20 by @ramarivera, with fixes applied.
# ============================================================================

Describe 'execute_with_timeout()'
  Include "$LIB_DIR/providers.sh"

  # Force non-TTY mode for consistent testing
  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
  }
  Before 'setup'

  cleanup() {
    unset CI
    unset GGA_NO_SPINNER
    unset GGA_TRACE
  }
  After 'cleanup'

  Describe 'successful command execution'
    It 'returns exit code 0 for successful command'
      When call execute_with_timeout 5 "TestProvider" echo "hello"
      The status should eq 0
      The output should include "hello"
      The stderr should include "Waiting for TestProvider"
    End

    It 'captures multi-line output'
      When call execute_with_timeout 5 "TestProvider" bash -c 'echo "Line 1"; echo "Line 2"; echo "Line 3"'
      The status should eq 0
      The output should include "Line 1"
      The output should include "Line 2"
      The output should include "Line 3"
      The stderr should be present
    End

    It 'executes bash function callbacks directly'
      my_callback() {
        echo "CALLBACK_OUTPUT:$1"
      }

      When call execute_with_timeout 5 "TestProvider" my_callback "arg1"
      The status should eq 0
      The output should include "CALLBACK_OUTPUT:arg1"
      The stderr should include "Waiting for TestProvider"
    End
  End

  Describe 'failed command execution'
    It 'returns non-zero exit code for failed command'
      When call execute_with_timeout 5 "TestProvider" bash -c "exit 42"
      The status should eq 42
      The output should include "(provider returned no output)"
      The stderr should be present
    End

    It 'captures stderr from failing command'
      When call execute_with_timeout 5 "TestProvider" bash -c "echo 'error message' >&2; exit 1"
      The status should eq 1
      # stdout+stderr are combined in output file
      The output should include "error message"
      The stderr should be present
    End

    It 'returns exit code 1 for false command'
      When call execute_with_timeout 5 "TestProvider" false
      The status should eq 1
      The output should include "(provider returned no output)"
      The stderr should be present
    End
  End

  Describe 'timeout behavior'
    It 'returns exit code 124 when command times out'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
    End

    It 'includes timeout duration in error message'
      When call execute_with_timeout 2 "SlowProvider" sleep 10
      The status should eq 124
      The stderr should include "2 seconds"
    End

    It 'suggests increasing TIMEOUT in error message'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "Increase TIMEOUT"
    End

    It 'terminates child processes after timeout'
      local marker
      marker=$(mktemp "${TEMP:-${TMPDIR:-/tmp}}/gga_timeout_marker.XXXXXX")
      rm -f "$marker"

      When call execute_with_timeout 1 "TestProvider" bash -c 'sleep 3; echo done > "$1"' _ "$marker"
      The status should eq 124
      The stderr should include "TIMEOUT"
      sleep 3
      Assert [ ! -e "$marker" ]
    End

    It 'kills child processes that ignore TERM'
      local marker
      marker=$(mktemp "${TEMP:-${TMPDIR:-/tmp}}/gga_timeout_marker.XXXXXX")
      rm -f "$marker"

      When call execute_with_timeout 1 "TestProvider" bash -c 'trap "" TERM; (trap "" TERM; sleep 3; echo done > "$1") & wait' _ "$marker"
      The status should eq 124
      The stderr should include "TIMEOUT"
      sleep 3
      Assert [ ! -e "$marker" ]
    End
  End

  Describe 'progress feedback in non-TTY mode'
    It 'shows waiting message on stderr'
      When call execute_with_timeout 5 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "Waiting for TestProvider"
      The output should include "done"
    End

    It 'includes timeout in waiting message'
      When call execute_with_timeout 10 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "10s"
      The output should include "done"
    End
  End

  Describe 'trace mode'
    setup_trace() {
      export CI=true
      export GGA_NO_SPINNER=1
      export GGA_TRACE=1
    }
    Before 'setup_trace'

    It 'shows trace output when GGA_TRACE is set'
      When call execute_with_timeout 5 "TestProvider" echo "test"
      The status should eq 0
      The stderr should include "[TRACE]"
      The output should include "test"
    End

    It 'shows exit code in trace'
      When call execute_with_timeout 5 "TestProvider" bash -c "exit 7"
      The status should eq 7
      The stderr should include "exit_code=7"
      The output should include "(provider returned no output)"
    End
  End

  Describe 'git environment sanitization'
    setup_git_env() {
      export CI=true
      export GGA_NO_SPINNER=1
      export GIT_DIR="/hook/git/dir"
      export GIT_INDEX_FILE="/hook/index"
      export GIT_WORK_TREE="/hook/wt"
      export GIT_PREFIX="sub/"
      export GIT_COMMON_DIR="/hook/common"
      export GIT_OBJECT_DIRECTORY="/hook/obj"
      export GIT_ALTERNATE_OBJECT_DIRECTORIES="/hook/alt"
      export GIT_QUARANTINE_PATH="/hook/quarantine"
    }
    Before 'setup_git_env'

    cleanup_git_env() {
      unset GIT_DIR
      unset GIT_INDEX_FILE
      unset GIT_WORK_TREE
      unset GIT_PREFIX
      unset GIT_COMMON_DIR
      unset GIT_OBJECT_DIRECTORY
      unset GIT_ALTERNATE_OBJECT_DIRECTORIES
      unset GIT_QUARANTINE_PATH
    }
    After 'cleanup_git_env'

    It 'sanitizes hook GIT_* environment variables from child command'
      When call execute_with_timeout 5 "TestProvider" bash -c 'env | grep "^GIT_" || echo "CLEAN"'
      The status should eq 0
      The output should include "CLEAN"
      The output should not include "GIT_DIR="
      The output should not include "GIT_INDEX_FILE="
      The output should not include "GIT_WORK_TREE="
      The output should not include "GIT_PREFIX="
      The output should not include "GIT_COMMON_DIR="
      The output should not include "GIT_OBJECT_DIRECTORY="
      The output should not include "GIT_ALTERNATE_OBJECT_DIRECTORIES="
      The output should not include "GIT_QUARANTINE_PATH="
      The stderr should include "Waiting for TestProvider"
    End

    It 'preserves caller git environment in parent shell'
      When call execute_with_timeout 5 "TestProvider" bash -c 'true'
      The status should eq 0
      The stderr should include "Waiting for TestProvider"
      The variable GIT_DIR should eq "/hook/git/dir"
      The variable GIT_INDEX_FILE should eq "/hook/index"
      The variable GIT_WORK_TREE should eq "/hook/wt"
      The variable GIT_PREFIX should eq "sub/"
      The variable GIT_COMMON_DIR should eq "/hook/common"
      The variable GIT_OBJECT_DIRECTORY should eq "/hook/obj"
      The variable GIT_ALTERNATE_OBJECT_DIRECTORIES should eq "/hook/alt"
      The variable GIT_QUARANTINE_PATH should eq "/hook/quarantine"
    End
  End

  Describe 'git index isolation during secondary operations'
    hash_file() {
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
      else
        cksum "$1" | awk '{print $1}'
      fi
    }

    setup_repos() {
      export CI=true
      export GGA_NO_SPINNER=1

      local base_tmp="/tmp/opencode"
      [[ -d "$base_tmp" ]] || base_tmp="${TEMP:-${TMPDIR:-/tmp}}"
      CALLER_REPO=$(mktemp -d "$base_tmp/gga_caller.XXXXXX")
      SECONDARY_REPO=$(mktemp -d "$base_tmp/gga_sec.XXXXXX")
      export CALLER_REPO SECONDARY_REPO

      # Isolate repository creation from any ambient or inherited Git variables
      unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX \
        GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH

      # Set up caller repository using Git plumbing without commits
      git init --quiet "$CALLER_REPO"
      local caller_blob
      caller_blob=$(echo "caller content" | git -C "$CALLER_REPO" hash-object -w --stdin)
      git -C "$CALLER_REPO" update-index --add --cacheinfo 100644 "$caller_blob" "file_a.txt"
      EXPECTED_TREE=$(git -C "$CALLER_REPO" write-tree)
      git -C "$CALLER_REPO" update-ref refs/tags/initial "$EXPECTED_TREE"
      EXPECTED_ENTRIES=$(git -C "$CALLER_REPO" ls-files -s)
      INITIAL_INDEX_HASH=$(hash_file "$CALLER_REPO/.git/index")
      export EXPECTED_TREE EXPECTED_ENTRIES INITIAL_INDEX_HASH

      # Set up secondary repository using Git plumbing without commits
      git init --quiet "$SECONDARY_REPO"
      local sec_blob
      sec_blob=$(echo "secondary content" | git -C "$SECONDARY_REPO" hash-object -w --stdin)
      git -C "$SECONDARY_REPO" update-index --add --cacheinfo 100644 "$sec_blob" "sec_file.txt"
      SECONDARY_TREE=$(git -C "$SECONDARY_REPO" write-tree)
      # Reset secondary index so read-tree demonstrably populates it
      git -C "$SECONDARY_REPO" read-tree --empty
      export SECONDARY_TREE

      # Set only GIT_INDEX_FILE to witness cross-object-store isolation
      export GIT_INDEX_FILE="$CALLER_REPO/.git/index"
    }
    Before 'setup_repos'

    cleanup_repos() {
      unset GIT_INDEX_FILE
      unset EXPECTED_TREE EXPECTED_ENTRIES INITIAL_INDEX_HASH SECONDARY_TREE

      if [[ -n "${CALLER_REPO:-}" && -d "$CALLER_REPO" ]]; then
        rm -rf "$CALLER_REPO"
      fi
      if [[ -n "${SECONDARY_REPO:-}" && -d "$SECONDARY_REPO" ]]; then
        rm -rf "$SECONDARY_REPO"
      fi
      unset CALLER_REPO SECONDARY_REPO
    }
    After 'cleanup_repos'

    It 'prevents secondary git operations from modifying caller index'
      When call execute_with_timeout 5 "TestProvider" git -C "$SECONDARY_REPO" read-tree "$SECONDARY_TREE"
      The status should eq 0
      The stderr should include "Waiting for TestProvider"
      Assert [ "$(hash_file "$CALLER_REPO/.git/index")" = "$INITIAL_INDEX_HASH" ]
      Assert [ "$(git -C "$CALLER_REPO" ls-files -s)" = "$EXPECTED_ENTRIES" ]
      Assert [ "$(git -C "$CALLER_REPO" write-tree)" = "$EXPECTED_TREE" ]
      Assert git -C "$CALLER_REPO" fsck --no-progress
      Assert [ "$(unset GIT_INDEX_FILE; git -C "$SECONDARY_REPO" write-tree)" = "$SECONDARY_TREE" ]
    End
  End
End

Describe 'execute_provider_with_timeout()'
  Include "$LIB_DIR/providers.sh"

  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
  }
  Before 'setup'

  cleanup() {
    unset CI
    unset GGA_NO_SPINNER
    unset OLLAMA_HOST
    unset LMSTUDIO_HOST
  }
  After 'cleanup'

  Describe 'generic fallback for unknown providers'
    It 'uses execute_provider as fallback instead of failing'
      # Mock execute_provider for the unknown provider
      execute_provider() {
        echo "FALLBACK_CALLED:$1"
      }

      When call execute_provider_with_timeout "some-new-provider" "test" 5
      The status should eq 0
      The output should include "FALLBACK_CALLED:some-new-provider"
      The stderr should be present
    End
  End

  Describe 'ollama host validation'
    It 'fails with invalid OLLAMA_HOST before attempting execution'
      OLLAMA_HOST="invalid://bad"

      When call execute_provider_with_timeout "ollama:llama3" "test" 5
      The status should be failure
      The stderr should include "Invalid OLLAMA_HOST"
    End
  End

  Describe 'lmstudio host validation'
    It 'fails with invalid LMSTUDIO_HOST before attempting execution'
      LMSTUDIO_HOST="invalid://bad"

      When call execute_provider_with_timeout "lmstudio" "test" 5
      The status should be failure
      The stderr should include "Invalid LMSTUDIO_HOST"
    End
  End

  Describe 'timeout parameter passing'
    It 'respects timeout parameter by timing out slow commands'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
    End
  End
End

Describe 'provider base extraction in timeout context'
  Include "$LIB_DIR/providers.sh"

  helper_get_base_provider() {
    local provider="$1"
    echo "${provider%%:*}"
  }

  It 'extracts base provider from simple provider'
    When call helper_get_base_provider "claude"
    The output should eq "claude"
  End

  It 'extracts base provider from ollama:model'
    When call helper_get_base_provider "ollama:llama3.2"
    The output should eq "ollama"
  End

  It 'extracts base provider from lmstudio:model'
    When call helper_get_base_provider "lmstudio:qwen"
    The output should eq "lmstudio"
  End
End
