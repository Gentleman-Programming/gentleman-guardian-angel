# shellcheck shell=bash

Describe 'Rules file configuration'
  # Path to the gga script
  gga() {
    "$PROJECT_ROOT/bin/gga" "$@"
  }

  Describe 'default rules file'
    It 'uses REVIEW_RULES.md as default'
      When call gga help
      The output should include "default: REVIEW_RULES.md"
    End

    It 'gga init creates config with REVIEW_RULES.md'
      temp_dir=$(mktemp -d)
      cd "$temp_dir"
      gga init > /dev/null
      The contents of file ".gga" should include 'RULES_FILE="REVIEW_RULES.md"'
      cd /
      rm -rf "$temp_dir"
    End
  End

  Describe 'AGENTS.md fallback (backwards compatibility)'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      git config user.email "test@test.com"
      git config user.name "Test"
      echo 'PROVIDER="claude"' > .gga
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'falls back to AGENTS.md when REVIEW_RULES.md does not exist'
      # Create only AGENTS.md (legacy file)
      echo "# Legacy rules" > AGENTS.md

      # Create a file to stage
      echo "test" > test.txt
      git add test.txt

      # Run should use AGENTS.md and show deprecation warning
      When call gga run
      The output should include "Using deprecated AGENTS.md"
      The output should include "rename to REVIEW_RULES.md"
    End

    It 'prefers REVIEW_RULES.md when both files exist'
      # Create both files
      echo "# New rules" > REVIEW_RULES.md
      echo "# Legacy rules" > AGENTS.md

      # Create a file to stage
      echo "test" > test.txt
      git add test.txt

      # Run should use REVIEW_RULES.md (no deprecation warning)
      When call gga run
      The output should include "Rules file: REVIEW_RULES.md"
      The output should not include "Using deprecated"
    End

    It 'fails when neither REVIEW_RULES.md nor AGENTS.md exists'
      # Don't create any rules file

      # Create a file to stage
      echo "test" > test.txt
      git add test.txt

      When call gga run
      The status should be failure
      The output should include "Rules file not found"
    End

    It 'respects custom RULES_FILE config over fallback'
      # Create custom rules file
      echo "# Custom rules" > custom_rules.md
      echo 'PROVIDER="claude"' > .gga
      echo 'RULES_FILE="custom_rules.md"' >> .gga

      # Also create AGENTS.md (should be ignored)
      echo "# Legacy rules" > AGENTS.md

      # Create a file to stage
      echo "test" > test.txt
      git add test.txt

      When call gga run
      The output should include "Rules file: custom_rules.md"
      The output should not include "Using deprecated"
    End
  End
End