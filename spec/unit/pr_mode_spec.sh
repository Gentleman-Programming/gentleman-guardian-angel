# shellcheck shell=bash

# ============================================================================
# PR Mode - Unit Tests
# ============================================================================
# Tests for --pr-mode and --diff-only functionality
# ============================================================================

Describe 'PR Mode'
  # We test the functions from bin/gga by sourcing them
  # Since bin/gga has a main() that runs immediately, we need to
  # extract the testable functions into lib/ or test indirectly.
  # For now, we test the helper functions that will be in lib/pr_mode.sh

  Include "$LIB_DIR/pr_mode.sh"

  Describe 'detect_base_branch()'
    It 'detects main as base branch'
      git() {
        case "$1" in
          branch)
            echo "  feat/my-feature"
            echo "  main"
            echo "  develop"
            ;;
        esac
      }

      When call detect_base_branch
      The output should eq "main"
      The status should be success
    End

    It 'detects master as base branch when main is not present'
      git() {
        case "$1" in
          branch)
            echo "  feat/my-feature"
            echo "  master"
            ;;
        esac
      }

      When call detect_base_branch
      The output should eq "master"
      The status should be success
    End

    It 'detects develop as base branch when main/master not present'
      git() {
        case "$1" in
          branch)
            echo "  feat/my-feature"
            echo "  develop"
            ;;
        esac
      }

      When call detect_base_branch
      The output should eq "develop"
      The status should be success
    End

    It 'prefers main over master when both exist'
      git() {
        case "$1" in
          branch)
            echo "  main"
            echo "  master"
            echo "  develop"
            ;;
        esac
      }

      When call detect_base_branch
      The output should eq "main"
      The status should be success
    End

    It 'fails when no known base branch is found'
      git() {
        case "$1" in
          branch)
            echo "  feat/my-feature"
            echo "  feat/other"
            ;;
        esac
      }

      When call detect_base_branch
      The status should be failure
      The stderr should include "Could not detect base branch"
    End

    It 'trims whitespace from branch names'
      git() {
        case "$1" in
          branch)
            echo "    main   "
            ;;
        esac
      }

      When call detect_base_branch
      The output should eq "main"
    End
  End

  Describe 'get_pr_range()'
    It 'returns base_branch...HEAD format'
      detect_base_branch() { echo "main"; }

      When call get_pr_range ""
      The output should eq "main...HEAD"
      The status should be success
    End

    It 'uses PR_BASE_BRANCH when provided'
      When call get_pr_range "release/v3"
      The output should eq "release/v3...HEAD"
      The status should be success
    End

    It 'uses auto-detected branch when PR_BASE_BRANCH is empty'
      detect_base_branch() { echo "develop"; }

      When call get_pr_range ""
      The output should eq "develop...HEAD"
    End

    It 'fails when detection fails and no override provided'
      detect_base_branch() { echo "Could not detect base branch" >&2; return 1; }

      When call get_pr_range ""
      The status should be failure
      The stderr should include "Could not detect base branch"
    End
  End

  Describe 'get_pr_files()'
    It 'returns files changed in PR range'
      git() {
        case "$1" in
          diff)
            echo "src/app.ts"
            echo "src/utils.ts"
            echo "tests/app.test.ts"
            ;;
        esac
      }

      # Skip file existence check in unit tests
      GGA_SKIP_FILE_CHECK=true
      When call get_pr_files "main...HEAD" "*" ""
      The output should include "src/app.ts"
      The output should include "src/utils.ts"
      The output should include "tests/app.test.ts"
    End

    It 'filters files by pattern'
      git() {
        case "$1" in
          diff)
            echo "src/app.ts"
            echo "src/utils.ts"
            echo "README.md"
            echo "package.json"
            ;;
        esac
      }

      GGA_SKIP_FILE_CHECK=true
      When call get_pr_files "main...HEAD" "*.ts" ""
      The output should include "src/app.ts"
      The output should include "src/utils.ts"
      The output should not include "README.md"
      The output should not include "package.json"
    End

    It 'excludes files matching exclude patterns'
      git() {
        case "$1" in
          diff)
            echo "src/app.ts"
            echo "src/app.test.ts"
            echo "src/utils.spec.ts"
            ;;
        esac
      }

      GGA_SKIP_FILE_CHECK=true
      When call get_pr_files "main...HEAD" "*.ts" "*.test.ts,*.spec.ts"
      The output should include "src/app.ts"
      The output should not include "src/app.test.ts"
      The output should not include "src/utils.spec.ts"
    End

    It 'returns empty when no files match patterns'
      git() {
        case "$1" in
          diff)
            echo "README.md"
            echo "package.json"
            ;;
        esac
      }

      GGA_SKIP_FILE_CHECK=true
      When call get_pr_files "main...HEAD" "*.ts" ""
      The output should eq ""
    End

    It 'accepts wildcard pattern to match all files'
      git() {
        case "$1" in
          diff)
            echo "src/app.ts"
            echo "README.md"
            echo "Makefile"
            ;;
        esac
      }

      GGA_SKIP_FILE_CHECK=true
      When call get_pr_files "main...HEAD" "*" ""
      The output should include "src/app.ts"
      The output should include "README.md"
      The output should include "Makefile"
    End
  End

  Describe 'get_pr_diff()'
    It 'returns diff output for the PR range'
      git() {
        case "$1" in
          diff)
            echo "diff --git a/src/app.ts b/src/app.ts"
            echo "+++ b/src/app.ts"
            echo "@@ -1,3 +1,4 @@"
            echo "+const x = 1;"
            ;;
        esac
      }

      When call get_pr_diff "main...HEAD"
      The output should include "diff --git"
      The output should include "+const x = 1;"
    End

    It 'returns empty when no diff exists'
      git() {
        case "$1" in
          diff) echo "" ;;
        esac
      }

      When call get_pr_diff "main...HEAD"
      The output should eq ""
    End
  End

  Describe 'validate_pr_mode_flags()'
    It 'succeeds with --pr-mode alone'
      When call validate_pr_mode_flags true false
      The status should be success
    End

    It 'succeeds with --pr-mode and --diff-only together'
      When call validate_pr_mode_flags true true
      The status should be success
    End

    It 'fails with --diff-only without --pr-mode'
      When call validate_pr_mode_flags false true
      The status should be failure
      The stderr should include "diff-only"
      The stderr should include "pr-mode"
    End

    It 'succeeds when neither flag is set'
      When call validate_pr_mode_flags false false
      The status should be success
    End
  End

  Describe 'build_pr_prompt()'
    It 'includes rules in the prompt'
      When call build_pr_prompt "My coding rules" "src/app.ts" false "" "main"
      The output should include "My coding rules"
      The output should include "CODING STANDARDS"
    End

    It 'includes file list in the prompt'
      When call build_pr_prompt "rules" "src/app.ts
src/utils.ts" false "" "main"
      The output should include "src/app.ts"
      The output should include "src/utils.ts"
    End

    It 'includes PR context mentioning the base branch'
      When call build_pr_prompt "rules" "src/app.ts" false "" "main"
      The output should include "pull request"
      The output should include "main"
    End

    It 'includes diff when diff_only mode is enabled'
      diff_content="diff --git a/src/app.ts b/src/app.ts
+++ b/src/app.ts
@@ -1,3 +1,4 @@
+const x = 1;"

      When call build_pr_prompt "rules" "src/app.ts" true "$diff_content" "main"
      The output should include "DIFF"
      The output should include "+const x = 1;"
    End

    It 'asks for STATUS in the response'
      When call build_pr_prompt "rules" "src/app.ts" false "" "main"
      The output should include "STATUS: PASSED"
      The output should include "STATUS: FAILED"
    End
  End
End
