# shellcheck shell=bash

Describe 'providers.sh pi support'
  Include "$LIB_DIR/providers.sh"

  ORIGINAL_PATH="$PATH"

  setup_pi_fixture() {
    FIXTURE_DIR=$(mktemp -d)
    mkdir -p "$FIXTURE_DIR/agent/pi-ext-roles" "$FIXTURE_DIR/bin"

    cat > "$FIXTURE_DIR/agent/pi-ext-roles/settings.json" <<'JSON'
{
  "modelAliases": {
    "reviewer-model": "reviewer-alias:high",
    "reviewer-alias": "vendor/primary-model",
    "loop-a": "loop-b",
    "loop-b": "loop-a"
  }
}
JSON

    cat > "$FIXTURE_DIR/bin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PI_ARGS_FILE"
cat > "$PI_STDIN_FILE"
# Pi's print mode prefixes the answer with an OSC 777 window notification.
printf '\033]777;notify;Pi;done\007'
printf 'STATUS: PASSED\n'
FAKE_PI
    chmod +x "$FIXTURE_DIR/bin/pi"

    PI_ARGS_FILE="$FIXTURE_DIR/argv"
    PI_STDIN_FILE="$FIXTURE_DIR/stdin"
    export PI_ARGS_FILE PI_STDIN_FILE
    PI_CODING_AGENT_DIR="$FIXTURE_DIR/agent"
    PI_HA_CONFIG="$FIXTURE_DIR/ha.json"
    PATH="$FIXTURE_DIR/bin:$ORIGINAL_PATH"
  }

  teardown_pi_fixture() {
    PATH="$ORIGINAL_PATH"
    rm -rf "$FIXTURE_DIR"
  }

  Before 'setup_pi_fixture'
  After 'teardown_pi_fixture'

  Describe 'resolve_pi_model()'
    It 'resolves the reviewer-model role alias chain with its effort'
      When call resolve_pi_model "reviewer-model"
      The status should be success
      The output should eq "vendor/primary-model:high"
    End

    It 'defaults to the reviewer-model role alias'
      When call resolve_pi_model ""
      The status should be success
      The output should eq "vendor/primary-model:high"
    End

    It 'honours an explicit trailing effort over the alias effort'
      When call resolve_pi_model "reviewer-model:off"
      The status should be success
      The output should eq "vendor/primary-model:off"
    End

    It 'keeps provider/model references verbatim'
      When call resolve_pi_model "vendor/other-model:low"
      The status should be success
      The output should eq "vendor/other-model:low"
    End

    It 'fails on an unknown alias instead of falling back'
      When call resolve_pi_model "missing-alias"
      The status should be failure
      The stderr should include "cannot resolve Pi model alias 'missing-alias'"
      The stderr should include "$FIXTURE_DIR/agent/pi-ext-roles/settings.json"
    End

    It 'fails on an alias chain that never resolves'
      When call resolve_pi_model "loop-a"
      The status should be failure
      The stderr should include "cannot resolve Pi model alias 'loop-a'"
    End

    It 'fails naming the settings file when the file is missing'
      PI_CODING_AGENT_DIR="$FIXTURE_DIR/missing"

      When call resolve_pi_model "reviewer-model"
      The status should be failure
      The stderr should include "$FIXTURE_DIR/missing/pi-ext-roles/settings.json"
    End
  End

  Describe 'get_provider_info()'
    It 'returns info for pi'
      When call get_provider_info "pi"
      The output should include "Pi CLI"
    End

    It 'returns info for pi with an explicit model'
      When call get_provider_info "pi:vendor/model:high"
      The output should include "model: vendor/model:high"
    End
  End

  Describe 'validate_provider() - pi'
    It 'succeeds when pi is installed and the role alias resolves'
      When call validate_provider "pi"
      The status should be success
    End

    It 'succeeds with an explicit provider/model reference'
      When call validate_provider "pi:vendor/other-model"
      The status should be success
    End

    It 'fails when pi is not on PATH'
      command() {
        case "$2" in
          pi) return 1 ;;
          *) builtin command "$@" ;;
        esac
      }

      When call validate_provider "pi"
      The status should be failure
      The output should include "Pi CLI not found"
    End

    It 'fails naming the settings file when the alias is unresolvable'
      When call validate_provider "pi:missing-alias"
      The status should be failure
      The stderr should include "$FIXTURE_DIR/agent/pi-ext-roles/settings.json"
    End
  End

  Describe 'execute_pi()'
    It 'strips the OSC 777 notification and returns the review'
      When call execute_pi "" "review prompt"
      The status should be success
      The output should eq "STATUS: PASSED"
    End

    It 'calls pi with a pure, offline review invocation'
      execute_pi "" "review prompt" >/dev/null

      The contents of file "$PI_ARGS_FILE" should include "--print"
      The contents of file "$PI_ARGS_FILE" should include "--no-session"
      The contents of file "$PI_ARGS_FILE" should include "--no-tools"
      The contents of file "$PI_ARGS_FILE" should include "--no-extensions"
      The contents of file "$PI_ARGS_FILE" should include "--no-skills"
      The contents of file "$PI_ARGS_FILE" should include "--no-prompt-templates"
      The contents of file "$PI_ARGS_FILE" should include "--no-themes"
      The contents of file "$PI_ARGS_FILE" should include "--no-context-files"
      The contents of file "$PI_ARGS_FILE" should include "--no-mcp"
      The contents of file "$PI_ARGS_FILE" should include "--offline"
      The contents of file "$PI_ARGS_FILE" should include "vendor/primary-model:high"
      The contents of file "$PI_STDIN_FILE" should eq "review prompt"
    End

    It 'passes an explicit model and effort to pi'
      execute_pi "vendor/other-model:low" "review prompt" >/dev/null

      The contents of file "$PI_ARGS_FILE" should include "vendor/other-model:low"
    End
  End

  Describe 'execute_provider_with_timeout() - pi'
    It 'sends the prompt through a temp file, never argv'
      execute_with_timeout() {
        shift 2
        "$@"
      }

      When call execute_provider_with_timeout "pi" "review prompt" 300
      The status should be success
      The output should include "STATUS: PASSED"
      The contents of file "$PI_STDIN_FILE" should eq "review prompt"
      The contents of file "$PI_ARGS_FILE" should not include "review prompt"
    End
  End

  Describe 'execute_pi() - reviewer group failover'
    write_ha_group() {
      cat > "$PI_HA_CONFIG" <<'JSON'
{
  "groups": {
    "reviewer": {
      "entries": [
        { "id": "vendor/primary-model" },
        { "id": "vendor/fallback-model" }
      ]
    }
  }
}
JSON
    }

    It 'tries the remaining reviewer entries and reports the failover'
      write_ha_group
      cat > "$FIXTURE_DIR/bin/pi" <<'FAILING_PI'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    vendor/primary-model) printf 'quota exceeded\n' >&2; exit 1 ;;
    vendor/fallback-model) printf 'STATUS: PASSED\n'; exit 0 ;;
  esac
done
exit 2
FAILING_PI
      chmod +x "$FIXTURE_DIR/bin/pi"

      When call execute_pi "vendor/primary-model" "review prompt"
      The status should be success
      The output should eq "STATUS: PASSED"
      The stderr should include "failing over to vendor/fallback-model"
    End

    It 'does not fail over for a model outside the reviewer group'
      write_ha_group
      cat > "$FIXTURE_DIR/bin/pi" <<'FAILING_PI'
#!/usr/bin/env bash
printf 'model unavailable\n' >&2
exit 1
FAILING_PI
      chmod +x "$FIXTURE_DIR/bin/pi"

      When call execute_pi "vendor/other-model" "review prompt"
      The status should be failure
      The stderr should include "model unavailable"
      The stderr should not include "failing over"
    End
  End
End
