#requires -Version 7
# Tests for mcp-resilience.ps1 (Invoke-McpWithRetry timeout + circuit-breaker)
# Dot-sourced (lib has no entrypoint) — resolve from repo scripts/lib via tests' parent dir
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\mcp-resilience.ps1')

Describe 'Invoke-McpWithRetry' {
    # Pester 6 isolation: functions dot-sourced at file root are NOT visible inside
    # It blocks — load the lib inside BeforeAll so it lives in the Describe scope.
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\mcp-resilience.ps1')
    }

    AfterEach {
        # ensure no circuit state leaks between retry/circuit tests
        Reset-McpCircuit -Server 'test-cb' -ErrorAction SilentlyContinue
    }

    It 'timeout: aborts a hanging scriptblock within TimeoutMs (no retry)' {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-McpWithRetry -Server 'test-timeout' -ScriptBlock { Start-Sleep -Seconds 60 } -TimeoutMs 500 -MaxRetries 0
        $sw.Stop()
        $r.Success | Should -BeFalse
        $r.Error | Should -Match 'Timed out'
        $sw.ElapsedMilliseconds | Should -BeLessThan 2000
    }

    It 'success: returns the scriptblock result synchronously' {
        $r = Invoke-McpWithRetry -Server 'test-ok' -ScriptBlock { 'hello' } -TimeoutMs 5000 -MaxRetries 0
        $r.Success | Should -BeTrue
        $r.Result | Should -Be 'hello'
    }

    It 'error: propagates scriptblock exceptions and retries up to MaxRetries' {
        $r = Invoke-McpWithRetry -Server 'test-err' -ScriptBlock { throw 'boom' } -TimeoutMs 5000 -MaxRetries 2 -BaseDelayMs 0
        $r.Success | Should -BeFalse
        $r.Attempts | Should -Be 3
        $r.Error | Should -Match 'boom'
    }

    It 'circuit: opens after 3 consecutive failures and fails fast' {
        Reset-McpCircuit -Server 'test-cb' -ErrorAction SilentlyContinue
        1..3 | ForEach-Object {
            $rr = Invoke-McpWithRetry -Server 'test-cb' -ScriptBlock { throw 'x' } -TimeoutMs 1000 -MaxRetries 0
            $rr.Success | Should -BeFalse
        }
        $r = Invoke-McpWithRetry -Server 'test-cb' -ScriptBlock { 'late' } -TimeoutMs 1000 -MaxRetries 0
        $r.CircuitState | Should -Be 'OPEN'
        $r.Error | Should -Match 'failing fast'
    }
}

