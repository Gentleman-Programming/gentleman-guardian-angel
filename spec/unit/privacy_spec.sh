# shellcheck shell=bash

Describe '_strip_private()'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"

  Describe 'explicit <private> tags'
    It 'redacts content inside private tags'
      result=$(_strip_private 'API key is <private>sk-abc123xyz</private> here')
      The value "$result" should eq 'API key is [REDACTED] here'
    End

    It 'redacts multiple private tags'
      result=$(_strip_private '<private>secret1</private> and <private>secret2</private>')
      The value "$result" should eq '[REDACTED] and [REDACTED]'
    End

    It 'returns unchanged text without secrets'
      result=$(_strip_private 'just normal text without secrets')
      The value "$result" should eq 'just normal text without secrets'
    End

    It 'handles empty input'
      When call _strip_private ""
      The status should be success
    End
  End

  Describe 'OpenAI key patterns'
    It 'redacts sk- prefixed keys'
      result=$(_strip_private 'key is sk-proj-abcdefghij1234567890')
      The value "$result" should include '[REDACTED]'
      The value "$result" should not include 'sk-proj-'
    End

    It 'redacts sk_live_ keys'
      result=$(_strip_private 'token sk_live_abcdefghij1234567890')
      The value "$result" should include '[REDACTED]'
    End

    It 'does not redact short sk- strings'
      result=$(_strip_private 'the sk-short key')
      The value "$result" should eq 'the sk-short key'
    End
  End

  Describe 'GitHub token patterns'
    It 'redacts ghp_ tokens'
      result=$(_strip_private 'token ghp_abcdefghij1234567890abcdefghij12')
      The value "$result" should include '[REDACTED]'
      The value "$result" should not include 'ghp_'
    End

    It 'redacts gho_ tokens'
      result=$(_strip_private 'oauth gho_abcdefghij1234567890')
      The value "$result" should include '[REDACTED]'
    End

    It 'redacts ghs_ tokens'
      result=$(_strip_private 'ghs_abcdefghij1234567890')
      The value "$result" should include '[REDACTED]'
    End
  End

  Describe 'Google API key patterns'
    It 'redacts AIza prefixed keys'
      result=$(_strip_private 'key AIzaSyB-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
      The value "$result" should include '[REDACTED]'
      The value "$result" should not include 'AIza'
    End
  End

  Describe 'Bearer and token patterns'
    It 'redacts Bearer tokens (mixed case)'
      result=$(_strip_private 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc123')
      The value "$result" should include '[REDACTED]'
      The value "$result" should not include 'eyJhbG'
    End

    It 'redacts token values'
      result=$(_strip_private 'header: token ghijklmnopqrstuvwxyz12345')
      The value "$result" should include '[REDACTED]'
    End

    It 'does not redact mentions of bearer in comments'
      result=$(_strip_private 'Use a Bearer tok')
      The value "$result" should eq 'Use a Bearer tok'
    End
  End

  Describe 'key=value secret patterns'
    It 'redacts password=value'
      result=$(_strip_private 'config: password=supersecret123')
      The value "$result" should include 'password=[REDACTED]'
      The value "$result" should not include 'supersecret'
    End

    It 'redacts api_key=value'
      result=$(_strip_private 'export api_key=abcdef12345')
      The value "$result" should include 'api_key=[REDACTED]'
    End

    It 'redacts SECRET=value (case insensitive)'
      result=$(_strip_private 'SECRET=my_secret_value_here')
      The value "$result" should include '[REDACTED]'
      The value "$result" should not include 'my_secret'
    End
  End

  Describe 'PEM private key redaction'
    It 'redacts single-line PEM (degenerate case)'
      result=$(_strip_private '-----BEGIN PRIVATE KEY-----MIIEvQIBADANBg-----END PRIVATE KEY-----')
      The value "$result" should include '[REDACTED_KEY]'
      The value "$result" should not include 'MIIEvQ'
    End

    It 'redacts multi-line PEM blocks'
      local pem_text
      pem_text=$(printf 'before\n-----BEGIN RSA PRIVATE KEY-----\nMIIBogIBAAJBAL\nRsGNmXnKhV1L\n-----END RSA PRIVATE KEY-----\nafter')
      result=$(_strip_private "$pem_text")
      The value "$result" should include '[REDACTED_KEY]'
      The value "$result" should include 'before'
      The value "$result" should include 'after'
      The value "$result" should not include 'MIIBog'
    End

    It 'redacts EC private keys'
      local pem_text
      pem_text=$(printf 'start\n-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg\n-----END EC PRIVATE KEY-----\nend')
      result=$(_strip_private "$pem_text")
      The value "$result" should include '[REDACTED_KEY]'
      The value "$result" should not include 'MHQCAQEEIBkg'
    End
  End

  Describe 'over-redaction protection'
    It 'does not redact normal code'
      result=$(_strip_private 'const password = getEnvVar("DB_PASS");')
      The value "$result" should include 'getEnvVar'
    End

    It 'preserves structure around redacted values'
      result=$(_strip_private 'cfg: api_key=secret123 timeout=30')
      The value "$result" should include 'timeout=30'
    End

    It 'does not redact short token-like strings'
      result=$(_strip_private 'use token abc')
      The value "$result" should eq 'use token abc'
    End
  End
End
