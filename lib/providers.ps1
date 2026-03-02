# ============================================================================
# Gentleman Guardian Angel - Provider Functions (PowerShell)
# ============================================================================

$script:ProvidersScriptPath = $MyInvocation.MyCommand.Path

function Test-Provider {
    param([string]$Provider)

    $baseProvider = ($Provider -split ':')[0]

    switch ($baseProvider) {
        "claude" {
            $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
            if (-not $claudeCmd) {
                Write-Color "Claude CLI not found" "Red"
                Write-Host ""
                Write-Host "Install Claude Code CLI:"
                Write-Host "  https://claude.ai/code"
                Write-Host ""
                return $false
            }
        }
        "gemini" {
            $geminiCmd = Get-Command gemini -ErrorAction SilentlyContinue
            if (-not $geminiCmd) {
                Write-Color "Gemini CLI not found" "Red"
                Write-Host ""
                Write-Host "Install Gemini CLI:"
                Write-Host "  npm install -g @anthropic-ai/gemini-cli"
                Write-Host ""
                return $false
            }
        }
        "codex" {
            $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
            if (-not $codexCmd) {
                Write-Color "Codex CLI not found" "Red"
                Write-Host ""
                Write-Host "Install OpenAI Codex CLI:"
                Write-Host "  npm install -g @openai/codex"
                Write-Host ""
                return $false
            }
        }
        "opencode" {
            $opencodeCmd = Get-Command opencode -ErrorAction SilentlyContinue
            if (-not $opencodeCmd) {
                Write-Color "OpenCode CLI not found" "Red"
                Write-Host ""
                Write-Host "Install OpenCode CLI:"
                Write-Host "  https://opencode.ai"
                Write-Host ""
                return $false
            }
        }
        "ollama" {
            $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
            if (-not $ollamaCmd) {
                Write-Color "Ollama not found" "Red"
                Write-Host ""
                Write-Host "Install Ollama:"
                Write-Host "  https://ollama.ai/download"
                Write-Host ""
                return $false
            }
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }
            if (-not $model) {
                Write-Color "Ollama requires a model" "Red"
                Write-Host ""
                Write-Host "Specify model in provider config:"
                Write-Host '  PROVIDER="ollama:llama3.2"'
                Write-Host '  PROVIDER="ollama:codellama"'
                Write-Host ""
                return $false
            }
        }
        "lmstudio" {
            $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
            if (-not $curlCmd) {
                Write-Color "curl not found" "Red"
                Write-Host ""
                Write-Host "Install curl:"
                Write-Host "  Most Windows systems have it pre-installed"
                Write-Host ""
                return $false
            }
        }
        "github" {
            $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
            if (-not $ghCmd) {
                Write-Color "gh CLI not found" "Red"
                Write-Host ""
                Write-Host "Install GitHub CLI:"
                Write-Host "  https://cli.github.com"
                Write-Host ""
                Write-Host "Then authenticate:"
                Write-Host "  gh auth login"
                Write-Host ""
                return $false
            }
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }
            if (-not $model) {
                Write-Color "GitHub Models requires a model" "Red"
                Write-Host ""
                Write-Host "Specify model in provider config:"
                Write-Host '  PROVIDER="github:gpt-4o"'
                Write-Host '  PROVIDER="github:deepseek-r1"'
                Write-Host ""
                return $false
            }
        }
        default {
            Write-Color "Unknown provider: $Provider" "Red"
            Write-Host ""
            Write-Host "Supported providers:"
            Write-Host "  - claude"
            Write-Host "  - gemini"
            Write-Host "  - codex"
            Write-Host "  - opencode"
            Write-Host "  - ollama:<model>"
            Write-Host "  - lmstudio[:model]"
            Write-Host "  - github:<model>"
            Write-Host ""
            return $false
        }
    }

    return $true
}

function Execute-Provider {
    param([string]$Provider, [string]$Prompt)

    $baseProvider = ($Provider -split ':')[0]

    switch ($baseProvider) {
        "claude" { Execute-Claude $Prompt }
        "gemini" { Execute-Gemini $Prompt }
        "codex" { Execute-Codex $Prompt }
        "opencode" {
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }
            Execute-Opencode $model $Prompt
        }
        "ollama" {
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "llama3.2" }
            Execute-Ollama $model $Prompt
        }
        "lmstudio" {
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }
            Execute-LmStudio $model $Prompt
        }
        "github" {
            $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }
            Execute-GitHubModels $model $Prompt
        }
    }
}

function Execute-Claude {
    param([string]$Prompt)
    $Prompt | claude --print 2>&1
    return $LASTEXITCODE
}

function Execute-Gemini {
    param([string]$Prompt)
    gemini -p $Prompt 2>&1
    return $LASTEXITCODE
}

function Execute-Codex {
    param([string]$Prompt)
    codex exec $Prompt 2>&1
    return $LASTEXITCODE
}

function Execute-Opencode {
    param([string]$Model, [string]$Prompt)
    if ($Model) {
        opencode run --model $Model $Prompt 2>&1
    } else {
        opencode run $Prompt 2>&1
    }
    return $LASTEXITCODE
}

function Execute-Ollama {
    param([string]$Model, [string]$Prompt)
    $ollamaHost = if ($env:OLLAMA_HOST) { $env:OLLAMA_HOST } else { "http://localhost:11434" }

    $ollamaHost = $ollamaHost.TrimEnd('/')

    try {
        $body = @{
            model = $Model
            prompt = $Prompt
            stream = $false
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$ollamaHost/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 300
        if ($response.response) {
            Write-Output $response.response
            return 0
        } elseif ($response.error) {
            Write-Error $response.error
            return 1
        } else {
            Write-Error "Unknown response from Ollama"
            return 1
        }
    } catch {
        Write-Error "Failed to connect to Ollama at $ollamaHost - $_"
        return 1
    }
}

function Execute-LmStudio {
    param([string]$Model, [string]$Prompt)
    $lmHost = if ($env:LMSTUDIO_HOST) { $env:LMSTUDIO_HOST } else { "http://localhost:1234/v1" }

    if (-not $lmHost.EndsWith("/v1")) {
        $lmHost = "$lmHost/v1"
    }

    if (-not $Model) { $Model = "local-model" }

    try {
        $body = @{
            model = $Model
            messages = @(
                @{ role = "user"; content = $Prompt }
            )
            temperature = 0.7
            stream = $false
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$lmHost/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 300
        if ($response.choices) {
            Write-Output $response.choices[0].message.content
            return 0
        } else {
            Write-Error "Unexpected response from LM Studio"
            return 1
        }
    } catch {
        Write-Error "Failed to connect to LM Studio at $lmHost - $_"
        return 1
    }
}

function Execute-GitHubModels {
    param([string]$Model, [string]$Prompt)

    $token = gh auth token 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI authentication failed. Run 'gh auth login'"
        return 1
    }

    $endpoint = "https://models.inference.ai.azure.com/chat/completions"

    try {
        $body = @{
            model = $Model
            messages = @(
                @{ role = "system"; content = "You are a helpful code review assistant." }
                @{ role = "user"; content = $Prompt }
            )
            temperature = 0.2
        } | ConvertTo-Json

        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $token"
        }

        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -Headers $headers -ContentType "application/json" -TimeoutSec 300
        if ($response.choices) {
            Write-Output $response.choices[0].message.content
            return 0
        } else {
            Write-Error "Unexpected response from GitHub Models"
            return 1
        }
    } catch {
        Write-Error "Failed to connect to GitHub Models - $_"
        return 1
    }
}

function Execute-ProviderWithTimeout {
    param([string]$Provider, [string]$Prompt, [int]$Timeout = 300)

    $baseProvider = ($Provider -split ':')[0]

    Write-Color "Waiting for $baseProvider response (timeout: ${Timeout}s)..." "Blue"

    $job = Start-Job -ScriptBlock {
        param($p, $pr, $providersPath)

        . $providersPath

        try {
            $rawOutput = @(Execute-Provider -Provider $p -Prompt $pr 2>&1)
            $exitCode = 0

            if ($rawOutput.Count -gt 0 -and $rawOutput[-1] -is [int]) {
                $exitCode = [int]$rawOutput[-1]
                if ($rawOutput.Count -gt 1) {
                    $rawOutput = $rawOutput[0..($rawOutput.Count - 2)]
                } else {
                    $rawOutput = @()
                }
            }

            $outputText = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"
            return [pscustomobject]@{
                Output = $outputText
                ExitCode = $exitCode
                TimedOut = $false
            }
        } catch {
            return [pscustomobject]@{
                Output = $_.Exception.Message
                ExitCode = 1
                TimedOut = $false
            }
        }
    } -ArgumentList $Provider, $Prompt, $script:ProvidersScriptPath

    $completed = Wait-Job $job -Timeout $Timeout

    if ($completed) {
        $result = Receive-Job $job
        Remove-Job $job -Force

        if ($result -is [array]) {
            return $result[-1]
        }
        return $result
    } else {
        Stop-Job $job
        Remove-Job $job -Force
        Write-Color "TIMEOUT: Provider did not respond within $Timeout seconds." "Red"
        return [pscustomobject]@{
            Output = ""
            ExitCode = 124
            TimedOut = $true
        }
    }
}

function Get-ProviderInfo {
    param([string]$Provider)

    $baseProvider = ($Provider -split ':')[0]
    $model = if ($Provider -match ':(.+)') { $matches[1] } else { "" }

    switch ($baseProvider) {
        "claude" { "Anthropic Claude Code CLI" }
        "gemini" { "Google Gemini CLI" }
        "codex" { "OpenAI Codex CLI" }
        "opencode" {
            if ($model) { "OpenCode CLI (model: $model)" } else { "OpenCode CLI" }
        }
        "ollama" { "Ollama (model: $model)" }
        "lmstudio" {
            if ($model) { "LM Studio (model: $model)" } else { "LM Studio" }
        }
        "github" { "GitHub Models (model: $model)" }
        default { "Unknown provider" }
    }
}
