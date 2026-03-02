# shellcheck shell=bash

Describe 'PowerShell hooks install/uninstall'
  setup() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
    GGA_PS1="$PROJECT_ROOT/bin/gga.ps1"
    PS_CMD="powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$GGA_PS1\""
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'install'
    It 'creates pre-commit hook at git-path hooks'
      eval "$PS_CMD install" >/dev/null 2>&1
      hooks_dir=$(git rev-parse --git-path hooks)
      The path "$hooks_dir/pre-commit" should be file
      The contents of file "$hooks_dir/pre-commit" should include "#!/bin/sh"
      The contents of file "$hooks_dir/pre-commit" should include "command -v pwsh"
      The contents of file "$hooks_dir/pre-commit" should include "powershell.exe"
      The contents of file "$hooks_dir/pre-commit" should include "gga run"
    End

    It 'creates commit-msg hook with positional file argument'
      eval "$PS_CMD install --commit-msg" >/dev/null 2>&1
      hooks_dir=$(git rev-parse --git-path hooks)
      The path "$hooks_dir/commit-msg" should be file
      The contents of file "$hooks_dir/commit-msg" should include "gga run \\\"\\$1\\\""
    End

    It 'inserts GGA block before final exit line'
      cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
echo "existing"
exit 0
EOF
      eval "$PS_CMD install" >/dev/null 2>&1

      gga_line=$(grep -n "GGA START" .git/hooks/pre-commit | cut -d: -f1)
      exit_line=$(grep -n "^exit 0" .git/hooks/pre-commit | tail -1 | cut -d: -f1)
      Assert [ "$gga_line" -lt "$exit_line" ]
    End
  End

  Describe 'uninstall'
    It 'removes marker block from mixed hook and preserves custom lines'
      cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
echo "existing"
# ======== GGA START ========
# Gentleman Guardian Angel - Code Review
gga run || exit 1
# ======== GGA END ========
echo "after"
EOF
      eval "$PS_CMD uninstall" >/dev/null 2>&1
      The path ".git/hooks/pre-commit" should be file
      The contents of file ".git/hooks/pre-commit" should include "existing"
      The contents of file ".git/hooks/pre-commit" should include "after"
      The contents of file ".git/hooks/pre-commit" should not include "GGA START"
    End

    It 'removes legacy gga run hook lines'
      cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
# Gentleman Guardian Angel - Code Review
gga run || exit 1
echo "after"
EOF
      eval "$PS_CMD uninstall" >/dev/null 2>&1
      The path ".git/hooks/pre-commit" should be file
      The contents of file ".git/hooks/pre-commit" should include "after"
      The contents of file ".git/hooks/pre-commit" should not include "gga run"
    End
  End
End
