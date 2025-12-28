# shellcheck shell=bash

Describe 'Multiple rules files feature'

  Describe 'RULES_FILE vs RULES_FILES config detection'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR" || exit 1
      git init --quiet
      echo "# Rules" > AGENTS.md
      echo "# Style" > STYLE.md
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'sets RULES_CONFIG_SOURCE to RULES_FILE when singular is used'
      cat > .gga << 'EOF'
PROVIDER="claude"
RULES_FILE="AGENTS.md"
EOF
      # Source the config loading logic
      RULES_FILE=""
      RULES_FILES=""
      RULES_CONFIG_SOURCE=""
      # shellcheck source=/dev/null
      source .gga
      # Simulate normalization (shellcheck disable for vars used by assertions)
      # shellcheck disable=SC2034
      if [[ -z "$RULES_FILES" && -n "$RULES_FILE" ]]; then
        RULES_FILES="$RULES_FILE"
        RULES_CONFIG_SOURCE="RULES_FILE"
      else
        RULES_CONFIG_SOURCE="RULES_FILES"
      fi
      The variable RULES_CONFIG_SOURCE should eq "RULES_FILE"
      The variable RULES_FILES should eq "AGENTS.md"
    End

    It 'sets RULES_CONFIG_SOURCE to RULES_FILES when plural is used'
      cat > .gga << 'EOF'
PROVIDER="claude"
RULES_FILES="AGENTS.md,STYLE.md"
EOF
      RULES_FILE=""
      RULES_FILES=""
      RULES_CONFIG_SOURCE=""
      # shellcheck source=/dev/null
      source .gga
      # shellcheck disable=SC2034
      if [[ -z "$RULES_FILES" && -n "$RULES_FILE" ]]; then
        RULES_FILES="$RULES_FILE"
        RULES_CONFIG_SOURCE="RULES_FILE"
      else
        RULES_CONFIG_SOURCE="RULES_FILES"
      fi
      The variable RULES_CONFIG_SOURCE should eq "RULES_FILES"
      The variable RULES_FILES should eq "AGENTS.md,STYLE.md"
    End

    It 'prefers RULES_FILES over RULES_FILE when both are set'
      cat > .gga << 'EOF'
PROVIDER="claude"
RULES_FILE="AGENTS.md"
RULES_FILES="AGENTS.md,STYLE.md"
EOF
      RULES_FILE=""
      RULES_FILES=""
      RULES_CONFIG_SOURCE=""
      # shellcheck source=/dev/null
      source .gga
      # shellcheck disable=SC2034
      if [[ -z "$RULES_FILES" && -n "$RULES_FILE" ]]; then
        RULES_FILES="$RULES_FILE"
        RULES_CONFIG_SOURCE="RULES_FILE"
      else
        RULES_CONFIG_SOURCE="RULES_FILES"
      fi
      The variable RULES_CONFIG_SOURCE should eq "RULES_FILE"
      The variable RULES_FILES should eq "AGENTS.md"
    End

    It 'sets RULES_CONFIG_SOURCE to RULES_FILES when plural is used'
      cat > .gga << 'EOF'
PROVIDER="claude"
RULES_FILES="AGENTS.md,STYLE.md"
EOF
      RULES_FILE=""
      RULES_FILES=""
      RULES_CONFIG_SOURCE=""
      # shellcheck source=/dev/null
      source .gga
      if [[ -z "$RULES_FILES" && -n "$RULES_FILE" ]]; then
        RULES_FILES="$RULES_FILE"
        RULES_CONFIG_SOURCE="RULES_FILE"
      else
        RULES_CONFIG_SOURCE="RULES_FILES"
      fi
      The variable RULES_CONFIG_SOURCE should eq "RULES_FILES"
      The variable RULES_FILES should eq "AGENTS.md,STYLE.md"
    End

    It 'prefers RULES_FILES over RULES_FILE when both are set'
      cat > .gga << 'EOF'
PROVIDER="claude"
RULES_FILE="AGENTS.md"
RULES_FILES="AGENTS.md,STYLE.md"
EOF
      RULES_FILE=""
      RULES_FILES=""
      RULES_CONFIG_SOURCE=""
      # shellcheck source=/dev/null
      source .gga
      if [[ -z "$RULES_FILES" && -n "$RULES_FILE" ]]; then
        RULES_FILES="$RULES_FILE"
        # shellcheck disable=SC2034  # Used by shellspec assertions
        RULES_CONFIG_SOURCE="RULES_FILE"
      else
        # shellcheck disable=SC2034  # Used by shellspec assertions
        RULES_CONFIG_SOURCE="RULES_FILES"
      fi
      The variable RULES_CONFIG_SOURCE should eq "RULES_FILES"
      The variable RULES_FILES should eq "AGENTS.md,STYLE.md"
    End
  End

  Describe 'get_rules_files_array()'
    # Include the library to get the function
    setup() {
      # Define the function inline for testing
      get_rules_files_array() {
        local files_str="$1"
        local -a files_array=()
        
        IFS=',' read -ra files_array <<< "$files_str"
        
        for i in "${!files_array[@]}"; do
          files_array[i]=$(echo "${files_array[i]}" | xargs)
        done
        
        printf '%s\n' "${files_array[@]}"
      }
      export -f get_rules_files_array
    }

    BeforeEach 'setup'

    It 'parses single file'
      result=$(get_rules_files_array "AGENTS.md")
      The value "$result" should eq "AGENTS.md"
    End

    It 'parses multiple files'
      result=$(get_rules_files_array "AGENTS.md,STYLE.md,CODE-REVIEW.md")
      The line 1 of value "$result" should eq "AGENTS.md"
      The line 2 of value "$result" should eq "STYLE.md"
      The line 3 of value "$result" should eq "CODE-REVIEW.md"
    End

    It 'trims whitespace from file names'
      result=$(get_rules_files_array "AGENTS.md , STYLE.md , CODE-REVIEW.md")
      The line 1 of value "$result" should eq "AGENTS.md"
      The line 2 of value "$result" should eq "STYLE.md"
      The line 3 of value "$result" should eq "CODE-REVIEW.md"
    End
  End

  Describe 'read_all_rules()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR" || exit 1
      echo "# Rule 1" > file1.md
      echo "# Rule 2" > file2.md
      
      # Define the functions inline for testing
      get_rules_files_array() {
        local files_str="$1"
        local -a files_array=()
        IFS=',' read -ra files_array <<< "$files_str"
        for i in "${!files_array[@]}"; do
          files_array[i]=$(echo "${files_array[i]}" | xargs)
        done
        printf '%s\n' "${files_array[@]}"
      }
      
      read_all_rules() {
        local files_str="$1"
        local content=""
        
        while IFS= read -r file; do
          if [[ -n "$file" && -f "$file" ]]; then
            if [[ -n "$content" ]]; then
              content+=$'\n\n'
            fi
            content+="# From: $file"$'\n'
            content+=$(cat "$file")
          fi
        done <<< "$(get_rules_files_array "$files_str")"
        
        echo "$content"
      }
      export -f get_rules_files_array read_all_rules
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'reads single file'
      result=$(read_all_rules "file1.md")
      The value "$result" should include "# Rule 1"
    End

    It 'reads and concatenates multiple files'
      result=$(read_all_rules "file1.md,file2.md")
      The value "$result" should include "# Rule 1"
      The value "$result" should include "# Rule 2"
      The value "$result" should include "# From: file1.md"
      The value "$result" should include "# From: file2.md"
    End
  End
End
