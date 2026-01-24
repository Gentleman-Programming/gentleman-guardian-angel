# shellcheck shell=bash

Describe 'CI mode (--ci)'
  
  setup() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
    
    # Create initial commit
    echo "initial" > README.md
    git add README.md
    git commit -m "initial commit" --quiet
    
    # Create config and rules
    echo 'PROVIDER="claude"' > .gga
    echo "# Rules" > AGENTS.md
    git add .gga AGENTS.md
    git commit -m "add config" --quiet
    
    GGA_BIN="$PROJECT_ROOT/bin/gga"
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'get_ci_files'
    It 'detects files changed in last commit'
      # Create a new commit with a test file
      echo "test content" > test.ts
      git add test.ts
      git commit -m "add test file" --quiet
      
      # Run in CI mode - should find test.ts
      When call "$GGA_BIN" run --ci
      The output should include "test.ts"
      The output should include "CI (reviewing last commit)"
    End

    It 'filters files by pattern'
      # Create files with different extensions
      echo "ts content" > file.ts
      echo "js content" > file.js
      echo "md content" > file.md
      git add .
      git commit -m "add files" --quiet
      
      # Update config to only review .ts files
      echo 'PROVIDER="claude"' > .gga
      echo 'FILE_PATTERNS="*.ts"' >> .gga
      
      When call "$GGA_BIN" run --ci
      The output should include "file.ts"
      The output should not include "file.js"
      The output should not include "file.md"
    End

    It 'shows warning when no matching files in last commit'
      # Last commit has AGENTS.md which doesn't match *.ts pattern
      echo 'PROVIDER="claude"' > .gga
      echo 'FILE_PATTERNS="*.ts"' >> .gga
      
      When call "$GGA_BIN" run --ci
      The output should include "No matching files changed in last commit"
      The status should be success
    End

    It 'disables cache in CI mode'
      echo "test" > test.ts
      git add test.ts
      git commit -m "add test" --quiet
      
      When call "$GGA_BIN" run --ci
      The output should include "disabled (CI mode)"
    End
  End

  Describe 'GGA_CI_SOURCE_COMMIT handling'
    It 'includes older changes when GGA_CI_SOURCE_COMMIT is set to include two commits'
      # Commit A (older): add old.ts
      echo "old" > old.ts
      git add old.ts
      git commit -m "add old file" --quiet

      # Commit B (newer): add new.ts
      echo "new" > new.ts
      git add new.ts
      git commit -m "add new file" --quiet

      # Run with GGA_CI_SOURCE_COMMIT set to include two commits back
      When call env GGA_CI_SOURCE_COMMIT=HEAD~2 "$GGA_BIN" run --ci
      The output should include "old.ts"
      The output should include "new.ts"
    End

    It 'only reviews last commit when GGA_CI_SOURCE_COMMIT is not set'
      # Commit A (older): add older.ts
      echo "older" > older.ts
      git add older.ts
      git commit -m "add older file" --quiet

      # Commit B (newer): add newer.ts
      echo "newer" > newer.ts
      git add newer.ts
      git commit -m "add newer file" --quiet

      # Run without GGA_CI_SOURCE_COMMIT - should only include the newest commit
      When call "$GGA_BIN" run --ci
      The output should include "newer.ts"
      The output should not include "older.ts"
    End
  End

  Describe 'excludes deleted files'
    It 'does not include files that were deleted'
      # Create and commit a file
      echo "content" > to_delete.ts
      git add to_delete.ts
      git commit -m "add file" --quiet
      
      # Delete it in next commit
      rm to_delete.ts
      git add to_delete.ts
      git commit -m "delete file" --quiet
      
      # CI mode should not try to review the deleted file
      When call "$GGA_BIN" run --ci
      The output should not include "to_delete.ts"
    End
  End
End
