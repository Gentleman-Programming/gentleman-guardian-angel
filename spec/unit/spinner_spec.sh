# shellcheck shell=bash

Describe 'Spinner functions'
  # Define colors used by spinner
  CYAN='\033[0;36m'
  NC='\033[0m'

  # Spinner state
  SPINNER_PID=""

  # Copy spinner functions for testing
  start_spinner() {
    local message="${1:-Processing...}"

    # Only show spinner if stdout is a terminal
    if [[ ! -t 1 ]]; then
      return
    fi

    local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    (
      local i=0
      local len=${#spinner_chars}
      while true; do
        local char="${spinner_chars:$i:1}"
        printf "\r${CYAN}%s${NC} %s" "$char" "$message"
        i=$(( (i + 1) % len ))
        sleep 0.1
      done
    ) &

    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
  }

  stop_spinner() {
    if [[ -z "$SPINNER_PID" ]]; then
      return
    fi

    if kill -0 "$SPINNER_PID" 2>/dev/null; then
      kill "$SPINNER_PID" 2>/dev/null || true
      wait "$SPINNER_PID" 2>/dev/null || true
    fi

    SPINNER_PID=""

    if [[ -t 1 ]]; then
      printf "\r\033[K"
    fi
  }

  Describe 'start_spinner()'
    It 'does not start spinner when stdout is not a terminal'
      # In test environment, stdout is typically not a terminal
      start_spinner "Test message"

      # SPINNER_PID should remain empty since stdout is not a tty
      The variable SPINNER_PID should equal ""
    End
  End

  Describe 'stop_spinner()'
    It 'does nothing when no spinner is running'
      SPINNER_PID=""

      # Should not error
      stop_spinner

      The variable SPINNER_PID should equal ""
    End

    It 'clears SPINNER_PID after stopping'
      # Simulate a running spinner by starting a background sleep
      sleep 10 &
      SPINNER_PID=$!

      stop_spinner

      The variable SPINNER_PID should equal ""
    End

    It 'kills the spinner process'
      # Start a background process
      sleep 10 &
      local test_pid=$!
      SPINNER_PID=$test_pid

      stop_spinner

      # Process should be killed
      if kill -0 "$test_pid" 2>/dev/null; then
        The value "process still running" should equal "process killed"
      else
        The value "process killed" should equal "process killed"
      fi
    End
  End

  Describe 'spinner integration'
    It 'can start and stop without errors in non-tty environment'
      # This tests the typical CI/test scenario
      start_spinner "Working..."
      stop_spinner

      # Should complete without errors
      The variable SPINNER_PID should equal ""
    End
  End
End