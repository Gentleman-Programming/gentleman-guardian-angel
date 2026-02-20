# shellcheck shell=bash

# Helper to check if jq is available
no_jq() {
  ! command -v jq &>/dev/null
}

Describe 'embeddings.sh'
  Include "$LIB_DIR/embeddings.sh"

  Skip if "jq not installed" no_jq

  Describe 'embed_openai()'
    It 'returns empty without API key'
      unset OPENAI_API_KEY
      When call embed_openai "test text"
      The status should be failure
    End

    It 'returns empty with empty text'
      export OPENAI_API_KEY="test-key"
      When call embed_openai ""
      The status should be failure
    End
  End

  Describe 'embed_gemini()'
    It 'returns empty without API key'
      unset GOOGLE_API_KEY
      When call embed_gemini "test text"
      The status should be failure
    End

    It 'returns empty with empty text'
      export GOOGLE_API_KEY="test-key"
      When call embed_gemini ""
      The status should be failure
    End
  End

  Describe 'embed_ollama()'
    It 'returns empty with empty text'
      When call embed_ollama ""
      The status should be failure
    End

    It 'fails gracefully when Ollama not running'
      export OLLAMA_HOST="http://localhost:99999"
      When call embed_ollama "test"
      The status should be failure
    End
  End

  Describe 'embed_github_models()'
    It 'returns empty without token'
      unset GITHUB_TOKEN
      When call embed_github_models "test text"
      The status should be failure
    End

    It 'returns empty with empty text'
      export GITHUB_TOKEN="test-token"
      When call embed_github_models ""
      The status should be failure
    End
  End

  Describe 'get_embedding()'
    It 'returns empty with empty text'
      When call get_embedding ""
      The status should be failure
    End

    It 'respects specific provider setting'
      export GGA_EMBED_PROVIDER="openai"
      unset OPENAI_API_KEY
      When call get_embedding "test"
      The status should be failure
    End

    It 'handles invalid provider gracefully'
      export GGA_EMBED_PROVIDER="invalid_provider"
      When call get_embedding "test"
      The output should equal ""
      The status should be failure
    End
  End

  Describe 'save_embedding()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      # Create minimal database
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE reviews (id INTEGER PRIMARY KEY, embedding TEXT);"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (id) VALUES (1);"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'saves embedding to database'
      When call save_embedding 1 '[0.1,0.2,0.3]'
      The status should be success
    End

    It 'fails with missing review_id'
      When call save_embedding "" '[0.1,0.2,0.3]'
      The status should be failure
    End

    It 'fails with missing embedding'
      When call save_embedding 1 ""
      The status should be failure
    End
  End

  Describe 'get_review_embedding()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE reviews (id INTEGER PRIMARY KEY, embedding TEXT);"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (id, embedding) VALUES (1, '[0.1,0.2,0.3]');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'retrieves embedding from database'
      When call get_review_embedding 1
      The output should equal '[0.1,0.2,0.3]'
    End

    It 'fails with missing review_id'
      When call get_review_embedding ""
      The status should be failure
    End
  End
End
