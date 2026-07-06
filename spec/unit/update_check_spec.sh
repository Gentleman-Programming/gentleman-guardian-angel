# shellcheck shell=bash

Describe 'check_update()'
  # Source the script variables and function directly
  setup() {
    VERSION="2.7.0"
    UPDATE_CHECK_REPO="Gentleman-Programming/gentleman-guardian-angel"
    YELLOW='\033[1;33m'
    NC='\033[0m'
  }

  BeforeEach 'setup'

  # Source check_update from the main script
  Include "$PROJECT_ROOT/bin/gga"

  Describe 'when a newer version is available'
    mock_curl() {
      echo '{"tag_name": "v2.8.0"}'
    }

    It 'shows update notification for major bump'
      CURL_CMD="mock_curl"
      VERSION="1.0.0"
      When call check_update
      The status should be success
      The output should include "Update available"
      The output should include "v1.0.0"
      The output should include "v2.8.0"
      The output should include "brew update && brew upgrade gga"
    End

    It 'shows update notification for minor bump'
      CURL_CMD="mock_curl"
      VERSION="2.7.0"
      When call check_update
      The status should be success
      The output should include "Update available"
      The output should include "v2.8.0"
    End

    It 'shows update notification for patch bump'
      mock_curl_patch() {
        echo '{"tag_name": "v2.7.1"}'
      }
      CURL_CMD="mock_curl_patch"
      VERSION="2.7.0"
      When call check_update
      The status should be success
      The output should include "Update available"
      The output should include "v2.7.1"
    End
  End

  Describe 'when already up to date'
    mock_curl_same() {
      echo '{"tag_name": "v2.7.0"}'
    }

    It 'shows nothing when versions match'
      CURL_CMD="mock_curl_same"
      VERSION="2.7.0"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End

  Describe 'when running a newer version than latest release'
    mock_curl_older() {
      echo '{"tag_name": "v2.6.0"}'
    }

    It 'shows nothing when local is newer'
      CURL_CMD="mock_curl_older"
      VERSION="2.7.0"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End

  Describe 'when network fails'
    mock_curl_fail() {
      return 1
    }

    It 'silently succeeds on curl failure'
      CURL_CMD="mock_curl_fail"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End

  Describe 'when response is invalid'
    mock_curl_invalid() {
      echo 'not json at all'
    }

    It 'silently succeeds on bad response'
      CURL_CMD="mock_curl_invalid"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End

  Describe 'when tag_name is empty'
    mock_curl_empty_tag() {
      echo '{"tag_name": ""}'
    }

    It 'silently succeeds on empty tag'
      CURL_CMD="mock_curl_empty_tag"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End

  Describe 'when running a dev build'
    mock_curl_dev() {
      echo '{"tag_name": "v2.8.0"}'
    }

    It 'skips update check entirely'
      CURL_CMD="mock_curl_dev"
      VERSION="dev"
      When call check_update
      The status should be success
      The output should equal ""
    End
  End
End
