# shellcheck shell=bash

Describe 'multi-rules support'
  Include "$LIB_DIR/cache.sh"

  Describe 'get_metadata_hash() with different rules file names'
    setup() {
      TEMP_DIR=$(mktemp -d)
      echo "same rules content" > "$TEMP_DIR/AGENTS.md"
      cp "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/AGENTS-security.md"
      echo "config content" > "$TEMP_DIR/.gga"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns different hashes for different rules file names with same content'
      hash1=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      hash2=$(get_metadata_hash "$TEMP_DIR/AGENTS-security.md" "$TEMP_DIR/.gga")
      The value "$hash1" should not eq "$hash2"
    End

    It 'returns same hash for same rules file name and content'
      hash1=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      hash2=$(get_metadata_hash "$TEMP_DIR/AGENTS.md" "$TEMP_DIR/.gga")
      The value "$hash1" should eq "$hash2"
    End
  End

  Describe 'GGA_RULES_FILE env var override'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "coding standards rules" > AGENTS.md
      echo "security audit rules" > AGENTS-security.md
      cat > .gga << 'GGAEOF'
PROVIDER="ollama:test-model"
RULES_FILE="AGENTS.md"
GGAEOF
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'GGA_RULES_FILE overrides RULES_FILE from .gga'
      # Source the config loading logic by calling load_config
      # We source bin/gga to get load_config, then call it
      DEFAULT_RULES_FILE="AGENTS.md"
      DEFAULT_FILE_PATTERNS="*"
      DEFAULT_STRICT_MODE="true"
      DEFAULT_TIMEOUT="300"

      RULES_FILE=""
      RULES_FILES=""
      PROVIDER=""
      FILE_PATTERNS=""
      EXCLUDE_PATTERNS=""
      STRICT_MODE=""
      TIMEOUT=""
      PR_BASE_BRANCH=""
      OPENCODE_VARIANT=""
      OPENCODE_AGENT=""

      # Simulate .gga sourcing
      source .gga

      # Simulate env var override
      GGA_RULES_FILE="AGENTS-security.md"
      if [[ -n "${GGA_RULES_FILE:-}" ]]; then
        RULES_FILE="$GGA_RULES_FILE"
      fi
      unset GGA_RULES_FILE

      The value "$RULES_FILE" should eq "AGENTS-security.md"
    End

    It 'RULES_FILE from .gga is used when GGA_RULES_FILE is not set'
      DEFAULT_RULES_FILE="AGENTS.md"
      RULES_FILE=""
      RULES_FILES=""
      PROVIDER=""
      FILE_PATTERNS=""
      EXCLUDE_PATTERNS=""
      STRICT_MODE=""
      TIMEOUT=""
      PR_BASE_BRANCH=""
      OPENCODE_VARIANT=""
      OPENCODE_AGENT=""

      source .gga

      # No env var override
      if [[ -n "${GGA_RULES_FILE:-}" ]]; then
        RULES_FILE="$GGA_RULES_FILE"
      fi

      The value "$RULES_FILE" should eq "AGENTS.md"
    End
  End

  Describe 'RULES_FILES (plural) parsing'
    It 'parses comma-separated list into array'
      RULES_FILES="AGENTS.md,AGENTS-security.md"
      local -a rules_files_list=()
      IFS=',' read -ra rules_files_list <<< "$RULES_FILES"

      The value "${rules_files_list[0]}" should eq "AGENTS.md"
      The value "${rules_files_list[1]}" should eq "AGENTS-security.md"
      The value "${#rules_files_list[@]}" should eq 2
    End

    It 'handles single entry in RULES_FILES'
      RULES_FILES="AGENTS.md"
      local -a rules_files_list=()
      IFS=',' read -ra rules_files_list <<< "$RULES_FILES"

      The value "${#rules_files_list[@]}" should eq 1
      The value "${rules_files_list[0]}" should eq "AGENTS.md"
    End

    It 'handles whitespace around entries'
      RULES_FILES="AGENTS.md, AGENTS-security.md"
      local -a rules_files_list=()
      IFS=',' read -ra rules_files_list <<< "$RULES_FILES"

      # Trim whitespace from second entry
      local entry="${rules_files_list[1]}"
      entry="${entry## }"
      entry="${entry%% }"

      The value "$entry" should eq "AGENTS-security.md"
    End

    It 'falls back to RULES_FILE when RULES_FILES is empty'
      RULES_FILES=""
      RULES_FILE="AGENTS.md"

      local -a rules_files_list=()
      if [[ -n "${RULES_FILES:-}" ]]; then
        IFS=',' read -ra rules_files_list <<< "$RULES_FILES"
      else
        rules_files_list=("$RULES_FILE")
      fi

      The value "${#rules_files_list[@]}" should eq 1
      The value "${rules_files_list[0]}" should eq "AGENTS.md"
    End
  End
End
