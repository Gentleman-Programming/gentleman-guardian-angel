# shellcheck shell=bash

# Tests for the ARG_MAX diagnostic. When a provider cannot be started because the
# prompt overflowed the OS argument limit, the shell reports exit 126 with a
# message that reads like a broken install ("Argument list too long", "bad
# interpreter: Permission denied"). Without guidance the user's next move is
# --no-verify, which disables the gate entirely.
#
# The negative case matters as much as the positive one: a genuine permission
# problem also exits 126, and must NOT be reported as an argument-limit issue.

Describe 'providers.sh ARG_MAX diagnostic on exit 126'
  Include "$LIB_DIR/providers.sh"

  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
    TEST_BIN_DIR="$(mktemp -d)"
    ORIGINAL_PATH="$PATH"
    PATH="$TEST_BIN_DIR:$PATH"

    # Fake provider: fails the way an oversized argv actually fails.
    cat > "$TEST_BIN_DIR/fake_e2big" <<'FAKE'
#!/usr/bin/env bash
echo "/usr/bin/fake: line 15: /usr/bin/node: Argument list too long" >&2
exit 126
FAKE

    # Fake provider: exits 126 for an unrelated reason.
    cat > "$TEST_BIN_DIR/fake_noexec" <<'FAKE'
#!/usr/bin/env bash
echo "some other failure" >&2
exit 126
FAKE

    chmod +x "$TEST_BIN_DIR/fake_e2big" "$TEST_BIN_DIR/fake_noexec"
  }

  cleanup() {
    PATH="$ORIGINAL_PATH"
    [[ -n "${TEST_BIN_DIR:-}" ]] && rm -rf "$TEST_BIN_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'explains the argument limit when exit 126 mentions it'
    When call execute_with_timeout 10 "FakeProvider" fake_e2big
    The status should equal 126
    The stderr should include "operating system argument limit"
    The stderr should include "Upgrade gga"
    The stderr should include "EXCLUDE_PATTERNS"
  End

  It 'still surfaces the raw provider output'
    When call execute_with_timeout 10 "FakeProvider" fake_e2big
    The status should equal 126
    The output should include "Argument list too long"
  End

  It 'stays quiet on an exit 126 that is not about the argument limit'
    When call execute_with_timeout 10 "FakeProvider" fake_noexec
    The status should equal 126
    The stderr should not include "operating system argument limit"
  End
End
