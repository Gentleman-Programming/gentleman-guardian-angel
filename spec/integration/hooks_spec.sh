# shellcheck shell=bash

Describe 'Git hooks install/uninstall'
  
  setup() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
    # Get the path to gga from the spec directory
    GGA_BIN="$PROJECT_ROOT/bin/gga"
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'cmd_install'
    It 'creates hook with markers in fresh repo'
      "$GGA_BIN" install >/dev/null 2>&1
      The path ".git/hooks/pre-commit" should be file
      The contents of file ".git/hooks/pre-commit" should include "# ======== GGA START ========"
      The contents of file ".git/hooks/pre-commit" should include "gga run || exit 1"
      The contents of file ".git/hooks/pre-commit" should include "# ======== GGA END ========"
    End

    It 'appends to existing hook with markers'
      mkdir -p .git/hooks
      cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
echo "existing hook"
EOF
      chmod +x .git/hooks/pre-commit
      
      "$GGA_BIN" install >/dev/null 2>&1
      
      The contents of file ".git/hooks/pre-commit" should include "existing hook"
      The contents of file ".git/hooks/pre-commit" should include "# ======== GGA START ========"
      The contents of file ".git/hooks/pre-commit" should include "gga run || exit 1"
    End

    It 'does not duplicate if already installed'
      "$GGA_BIN" install >/dev/null 2>&1
      "$GGA_BIN" install >/dev/null 2>&1
      
      # Count occurrences of GGA START
      count=$(grep -c "GGA START" .git/hooks/pre-commit)
      The value "$count" should eq "1"
    End

    It 'uses git-path hooks for hook path (worktree compatible)'
      # The hook should be installed at $(git rev-parse --git-path hooks)/
      # This correctly resolves to main repo's hooks even in worktrees
      "$GGA_BIN" install >/dev/null 2>&1
      
      hooks_dir=$(git rev-parse --git-path hooks)
      The path "$hooks_dir/pre-commit" should be file
    End

    It 'inserts before exit 0 in existing hook'
      mkdir -p .git/hooks
      cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
echo "other hook logic"
exit 0
EOF
      chmod +x .git/hooks/pre-commit
      
      "$GGA_BIN" install >/dev/null 2>&1
      
      # GGA should appear BEFORE the final exit 0
      # Get line numbers
      gga_line=$(grep -n "GGA START" .git/hooks/pre-commit | cut -d: -f1)
      exit_line=$(grep -n "^exit 0" .git/hooks/pre-commit | tail -1 | cut -d: -f1)
      
      # GGA line should be less than exit line (appears before)
      The value "$gga_line" should be present
      The value "$exit_line" should be present
      # Assert GGA comes before exit - using test command with assertion
      Assert [ "$gga_line" -lt "$exit_line" ]
    End
  End

  Describe 'cmd_uninstall'
    It 'removes GGA-only hook file completely'
      "$GGA_BIN" install >/dev/null 2>&1
      "$GGA_BIN" uninstall >/dev/null 2>&1
      
      The path ".git/hooks/pre-commit" should not be exist
    End

    It 'removes only GGA section from mixed hook'
      mkdir -p .git/hooks
      cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
echo "existing hook"
EOF
      chmod +x .git/hooks/pre-commit
      
      "$GGA_BIN" install >/dev/null 2>&1
      "$GGA_BIN" uninstall >/dev/null 2>&1
      
      The path ".git/hooks/pre-commit" should be file
      The contents of file ".git/hooks/pre-commit" should include "existing hook"
      The contents of file ".git/hooks/pre-commit" should not include "GGA START"
      The contents of file ".git/hooks/pre-commit" should not include "gga run"
    End

    It 'handles legacy hooks without markers'
      mkdir -p .git/hooks
      cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
# Gentleman Guardian Angel
gga run || exit 1
EOF
      chmod +x .git/hooks/pre-commit
      
      "$GGA_BIN" uninstall >/dev/null 2>&1
      
      The path ".git/hooks/pre-commit" should not be exist
    End
  End
End
