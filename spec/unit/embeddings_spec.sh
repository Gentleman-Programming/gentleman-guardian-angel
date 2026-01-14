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

    It 'fails without database'
      export GGA_DB_PATH="/nonexistent/path.db"
      When call get_review_embedding 1
      The status should be failure
    End
  End

  Describe 'embed_review()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE reviews (id INTEGER PRIMARY KEY, files TEXT, result TEXT, embedding TEXT);"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (id, files, result) VALUES (1, 'auth.ts', 'Security issue found');"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (id, files, result) VALUES (2, '', '');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'fails with missing review_id'
      When call embed_review ""
      The status should be failure
    End

    It 'fails without database'
      export GGA_DB_PATH="/nonexistent/path.db"
      When call embed_review 1
      The status should be failure
    End

    It 'fails when review has no content'
      When call embed_review 2
      The status should be failure
    End

    It 'calls get_embedding with review content'
      # Mock get_embedding to track what was called
      get_embedding() {
        echo "CALLED:$1" >&2
        echo '[0.1,0.2,0.3]'
      }
      save_embedding() { return 0; }

      When call embed_review 1
      The status should be success
      The stderr should include "auth.ts"
      The stderr should include "Security issue found"
    End

    It 'saves embedding after generation'
      get_embedding() { echo '[0.5,0.6,0.7]'; }

      When call embed_review 1
      The status should be success
      # Verify embedding was saved
      local saved
      saved=$(sqlite3 "$GGA_DB_PATH" "SELECT embedding FROM reviews WHERE id=1;")
      Assert [ "$saved" = "[0.5,0.6,0.7]" ]
    End

    It 'fails when embedding generation fails'
      get_embedding() { echo ""; return 1; }

      When call embed_review 1
      The status should be failure
    End
  End

  Describe 'get_embedding() fallback chain'
    It 'uses ollama first in auto mode'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo '[0.1,0.2]'; }
      embed_gemini() { echo '[0.3,0.4]'; }

      When call get_embedding "test"
      The output should eq '[0.1,0.2]'
    End

    It 'falls back to gemini when ollama fails'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo ""; return 1; }
      embed_gemini() { echo '[0.3,0.4]'; }

      When call get_embedding "test"
      The output should eq '[0.3,0.4]'
    End

    It 'falls back to github when gemini fails'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo ""; return 1; }
      embed_gemini() { echo ""; return 1; }
      embed_github_models() { echo '[0.5,0.6]'; }

      When call get_embedding "test"
      The output should eq '[0.5,0.6]'
    End

    It 'falls back to openai when github fails'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo ""; return 1; }
      embed_gemini() { echo ""; return 1; }
      embed_github_models() { echo ""; return 1; }
      embed_openai() { echo '[0.7,0.8]'; }

      When call get_embedding "test"
      The output should eq '[0.7,0.8]'
    End

    It 'returns empty when all providers fail'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo ""; return 1; }
      embed_gemini() { echo ""; return 1; }
      embed_github_models() { echo ""; return 1; }
      embed_openai() { echo ""; return 1; }

      When call get_embedding "test"
      The output should eq ""
      The status should be failure
    End

    It 'skips null responses in fallback'
      export GGA_EMBED_PROVIDER="auto"
      embed_ollama() { echo "null"; }
      embed_gemini() { echo '[0.3,0.4]'; }

      When call get_embedding "test"
      The output should eq '[0.3,0.4]'
    End
  End

  Describe 'get_embedding() specific providers'
    It 'uses gemini when specified'
      export GGA_EMBED_PROVIDER="gemini"
      embed_gemini() { echo '[1.0,2.0]'; }
      embed_ollama() { echo '[0.1,0.2]'; }

      When call get_embedding "test"
      The output should eq '[1.0,2.0]'
    End

    It 'uses github-models when specified'
      export GGA_EMBED_PROVIDER="github-models"
      embed_github_models() { echo '[3.0,4.0]'; }

      When call get_embedding "test"
      The output should eq '[3.0,4.0]'
    End

    It 'uses github as alias for github-models'
      export GGA_EMBED_PROVIDER="github"
      embed_github_models() { echo '[5.0,6.0]'; }

      When call get_embedding "test"
      The output should eq '[5.0,6.0]'
    End
  End
End
