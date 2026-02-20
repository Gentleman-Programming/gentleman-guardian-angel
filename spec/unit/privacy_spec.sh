# shellcheck shell=bash

Describe 'privacy stripping (_strip_private)'
  Include "$LIB_DIR/sqlite.sh"

  Describe '_strip_private()'
    It 'returns empty for empty input'
      When call _strip_private ""
      The status should be success
      The output should eq ""
    End

    It 'passes through clean text unchanged'
      When call _strip_private "normal code review text"
      The output should eq "normal code review text"
    End

    # Layer 1: Explicit <private> tags
    Describe 'explicit tags'
      It 'strips <private> tags'
        When call _strip_private 'API key is <private>sk-abc123secret</private> here'
        The output should eq 'API key is [REDACTED] here'
      End

      It 'strips multiple <private> tags'
        When call _strip_private 'key=<private>aaa</private> secret=<private>bbb</private>'
        The output should eq 'key=[REDACTED] secret=[REDACTED]'
      End
    End

    # Layer 2: Common secret patterns
    Describe 'OpenAI keys'
      It 'strips sk- prefixed keys'
        When call _strip_private 'Using key sk-proj1234567890abcdef'
        The output should include '[REDACTED]'
        The output should not include 'sk-proj1234567890'
      End

      It 'strips sk_live_ keys'
        When call _strip_private 'stripe key sk_live_1234567890abcdef'
        The output should include '[REDACTED]'
        The output should not include 'sk_live_'
      End
    End

    Describe 'GitHub tokens'
      It 'strips ghp_ tokens'
        When call _strip_private 'token ghp_ABCdef1234567890abcdef1234567890abcd'
        The output should include '[REDACTED]'
        The output should not include 'ghp_'
      End

      It 'strips gho_ tokens'
        When call _strip_private 'auth gho_ABCdef1234567890'
        The output should include '[REDACTED]'
        The output should not include 'gho_'
      End
    End

    Describe 'Google API keys'
      It 'strips AIza-prefixed keys'
        When call _strip_private 'google key AIzaSyA1234567890abcdefghijklmnopqrst'
        The output should include '[REDACTED]'
        The output should not include 'AIza'
      End
    End

    Describe 'Bearer tokens'
      It 'strips Bearer tokens'
        When call _strip_private 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkw'
        The output should include 'Bearer [REDACTED]'
        The output should not include 'eyJhbG'
      End

      It 'strips token keyword (case insensitive)'
        When call _strip_private 'Token abcdef1234567890abcdef1234'
        The output should include 'Token [REDACTED]'
      End
    End

    Describe 'key=value patterns'
      It 'strips password=value'
        When call _strip_private 'config password=mysecretpass123'
        The output should include 'password=[REDACTED]'
        The output should not include 'mysecretpass'
      End

      It 'strips api_key=value'
        When call _strip_private 'set api_key=abcdef123456'
        The output should include 'api_key=[REDACTED]'
        The output should not include 'abcdef'
      End

      It 'strips secret=value'
        When call _strip_private 'export secret=supersecret'
        The output should include 'secret=[REDACTED]'
        The output should not include 'supersecret'
      End

      It 'strips access_token=value'
        When call _strip_private 'access_token=tok_123abc'
        The output should include 'access_token=[REDACTED]'
        The output should not include 'tok_123'
      End

      It 'is case insensitive for key names'
        When call _strip_private 'PASSWORD=secret123 API_KEY=key456'
        The output should include 'PASSWORD=[REDACTED]'
        The output should include 'API_KEY=[REDACTED]'
      End
    End

    Describe 'mixed patterns'
      It 'strips multiple different patterns in one text'
        local text='diff: password=abc123 and ghp_tokenvalue1234567890 found'
        When call _strip_private "$text"
        The output should include 'password=[REDACTED]'
        The output should include '[REDACTED]'
        The output should not include 'abc123'
        The output should not include 'ghp_token'
      End

      It 'preserves non-secret content around redactions'
        When call _strip_private 'line 1: ok
line 2: password=secret here
line 3: also ok'
        The output should include 'line 1: ok'
        The output should include 'password=[REDACTED]'
        The output should include 'line 3: also ok'
      End
    End

    Describe 'does not over-redact'
      It 'keeps short sk- strings (not keys)'
        When call _strip_private 'variable sk-short'
        The output should eq 'variable sk-short'
      End

      It 'keeps normal password mentions'
        When call _strip_private 'check the password field'
        The output should eq 'check the password field'
      End

      It 'keeps normal token mentions'
        When call _strip_private 'JWT token validation logic'
        The output should eq 'JWT token validation logic'
      End
    End
  End
End
