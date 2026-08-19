# shellcheck shell=bash

Describe 'Retry and fallback functionality'
  Include lib/providers.sh

  MOCK_STATE_DIR=""

  setup() {
    MOCK_STATE_DIR=$(mktemp -d)
    echo "0" > "$MOCK_STATE_DIR/call_count"
    echo "0" > "$MOCK_STATE_DIR/fail_count"
    echo "1" > "$MOCK_STATE_DIR/fail_status"
  }

  cleanup() {
    rm -rf "$MOCK_STATE_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  # Mock sleep so backoff does not actually wait, and record the delays
  sleep() {
    echo "$1" >> "$MOCK_STATE_DIR/sleep_calls"
  }

  # Stand in for the real executor. execute_with_retry() calls this by name,
  # so the function under test is the real one, not a copy.
  execute_provider_with_timeout() {
    local provider="$1"
    local timeout="$3"

    local count
    count=$(cat "$MOCK_STATE_DIR/call_count")
    count=$((count + 1))
    echo "$count" > "$MOCK_STATE_DIR/call_count"
    echo "$provider" >> "$MOCK_STATE_DIR/providers"
    echo "$timeout" >> "$MOCK_STATE_DIR/timeouts"

    local fail_count fail_status
    fail_count=$(cat "$MOCK_STATE_DIR/fail_count")
    fail_status=$(cat "$MOCK_STATE_DIR/fail_status")

    if [[ $count -le $fail_count ]]; then
      echo "Error: Mock failure $count" >&2
      return "$fail_status"
    fi
    echo "SUCCESS: Mock response from $provider"
    return 0
  }

  # Every fallback provider is considered installed unless a test says otherwise
  validate_provider() {
    [[ "${MOCK_FALLBACK_AVAILABLE:-true}" == "true" ]]
  }

  get_call_count() { cat "$MOCK_STATE_DIR/call_count"; }
  set_fail_count() { echo "$1" > "$MOCK_STATE_DIR/fail_count"; }
  set_fail_status() { echo "$1" > "$MOCK_STATE_DIR/fail_status"; }

  Describe 'execute_with_retry()'
    It 'succeeds on first attempt'
      set_fail_count 0

      result=$(execute_with_retry "claude" "test prompt" 300 3 1 "" 2>/dev/null)

      The value "$result" should include "SUCCESS"
      The value "$(get_call_count)" should equal "1"
    End

    It 'retries on failure and succeeds on third attempt'
      set_fail_count 2

      result=$(execute_with_retry "claude" "test prompt" 300 3 1 "" 2>/dev/null)

      The value "$result" should include "SUCCESS"
      The value "$(get_call_count)" should equal "3"
    End

    It 'fails after all retries exhausted'
      set_fail_count 10

      status=0
      execute_with_retry "claude" "test prompt" 300 3 1 "" 2>/dev/null || status=$?

      The value "$status" should equal "1"
      The value "$(get_call_count)" should equal "3"
    End

    It 'respects retry count parameter'
      set_fail_count 10

      execute_with_retry "claude" "test prompt" 300 5 1 "" 2>/dev/null || true

      The value "$(get_call_count)" should equal "5"
    End

    It 'forwards the timeout to the executor'
      set_fail_count 0

      execute_with_retry "claude" "test prompt" 42 3 1 "" >/dev/null 2>&1

      The contents of file "$MOCK_STATE_DIR/timeouts" should include "42"
    End

    It 'propagates a timeout exit code instead of collapsing it to 1'
      set_fail_count 10
      set_fail_status 124

      status=0
      execute_with_retry "claude" "test prompt" 300 2 1 "" 2>/dev/null || status=$?

      The value "$status" should equal "124"
    End
  End

  Describe 'fallback provider'
    It 'uses the fallback when the primary is exhausted'
      set_fail_count 3

      result=$(execute_with_retry "claude" "test prompt" 300 3 1 "gemini" 2>/dev/null)

      The value "$result" should include "SUCCESS"
      The value "$result" should include "gemini"
      The value "$(get_call_count)" should equal "4"
    End

    It 'gives the fallback a single attempt, not a full retry budget'
      set_fail_count 100

      status=0
      execute_with_retry "claude" "test prompt" 300 3 1 "gemini" 2>/dev/null || status=$?

      The value "$status" should equal "1"
      The value "$(get_call_count)" should equal "4"
    End

    It 'does not call an unavailable fallback'
      set_fail_count 100
      MOCK_FALLBACK_AVAILABLE=false

      status=0
      execute_with_retry "claude" "test prompt" 300 3 1 "gemini" 2>/dev/null || status=$?
      MOCK_FALLBACK_AVAILABLE=true

      The value "$status" should equal "1"
      The value "$(get_call_count)" should equal "3"
    End

    It 'works without a fallback configured'
      set_fail_count 3

      status=0
      execute_with_retry "claude" "test prompt" 300 3 1 "" 2>/dev/null || status=$?

      The value "$status" should equal "1"
      The value "$(get_call_count)" should equal "3"
    End
  End

  Describe 'logging' 
    It 'logs retry attempts to stderr'
      set_fail_count 2

      stderr=$(execute_with_retry "claude" "test prompt" 300 3 1 "" 2>&1 >/dev/null)

      The value "$stderr" should include "failed"
      The value "$stderr" should include "attempt"
      The value "$stderr" should include "Retrying"
    End

    It 'labels a timeout as a timeout, not a generic failure'
      set_fail_count 2
      set_fail_status 124

      stderr=$(execute_with_retry "claude" "test prompt" 77 3 1 "" 2>&1 >/dev/null)

      The value "$stderr" should include "timed out"
      The value "$stderr" should include "77"
    End

    It 'logs the fallback attempt to stderr'
      set_fail_count 3

      stderr=$(execute_with_retry "claude" "test prompt" 300 3 1 "gemini" 2>&1 >/dev/null)

      The value "$stderr" should include "fallback"
      The value "$stderr" should include "gemini"
    End
  End

  Describe 'exponential backoff'
    It 'doubles the delay on each retry'
      set_fail_count 10

      execute_with_retry "claude" "test prompt" 300 4 2 "" 2>/dev/null || true

      sleep_calls=$(cat "$MOCK_STATE_DIR/sleep_calls" 2>/dev/null || echo "")

      # 3 retries after the initial attempt: 2, 4, 8
      The value "$sleep_calls" should include "2"
      The value "$sleep_calls" should include "4"
      The value "$sleep_calls" should include "8"
    End
  End
End
