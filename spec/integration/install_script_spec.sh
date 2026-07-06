# shellcheck shell=bash

Describe 'install.sh'
  setup() {
    TEMP_DIR=$(mktemp -d)
    FAKE_INSTALL_DIR="$TEMP_DIR/bin"
    mkdir -p "$FAKE_INSTALL_DIR"
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'copies all required lib files'
    It 'copies providers.sh to lib directory'
      HOME="$TEMP_DIR" INSTALL_DIR="$FAKE_INSTALL_DIR" \
        bash -c 'echo "y" | bash "$1/install.sh"' _ "$PROJECT_ROOT" 2>/dev/null
      The path "$TEMP_DIR/.local/share/gga/lib/providers.sh" should be file
    End

    It 'copies cache.sh to lib directory'
      HOME="$TEMP_DIR" INSTALL_DIR="$FAKE_INSTALL_DIR" \
        bash -c 'echo "y" | bash "$1/install.sh"' _ "$PROJECT_ROOT" 2>/dev/null
      The path "$TEMP_DIR/.local/share/gga/lib/cache.sh" should be file
    End

    It 'copies pr_mode.sh to lib directory'
      HOME="$TEMP_DIR" INSTALL_DIR="$FAKE_INSTALL_DIR" \
        bash -c 'echo "y" | bash "$1/install.sh"' _ "$PROJECT_ROOT" 2>/dev/null
      The path "$TEMP_DIR/.local/share/gga/lib/pr_mode.sh" should be file
    End

    It 'creates a cmd.exe wrapper on Windows'
      HOME="$TEMP_DIR" GGA_TEST_OS="windows" \
        bash -c 'echo "y" | bash "$1/install.sh"' _ "$PROJECT_ROOT" 2>/dev/null
      The path "$TEMP_DIR/bin/gga.bat" should be file
      The contents of file "$TEMP_DIR/bin/gga.bat" should include "where git"
      The contents of file "$TEMP_DIR/bin/gga.bat" should include "where bash"
      The contents of file "$TEMP_DIR/bin/gga.bat" should include "bash.exe"
      The contents of file "$TEMP_DIR/bin/gga.bat" should include "%~dp0gga"
    End
  End
End
