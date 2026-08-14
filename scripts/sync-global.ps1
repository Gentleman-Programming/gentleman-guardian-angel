#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Sync gentleman-agent-gh to global OpenCode config — skills, scripts, MCPs, agents, AGENTS.md, permissions.
.DESCRIPTION
    One-shot pipeline: skill junctions, scripts junction, global opencode.jsonc with MCPs + permissions, agent sync, AGENTS.md, MCP verification.
.PARAMETER DryRun  Show what would be done without making changes.
.PARAMETER Force  Overwrite existing global opencode.jsonc.
.PARAMETER NoAgentSync  Skip agent + AGENTS.md sync.
.PARAMETER Json  Output status as JSON.
#>
param([switch]$DryRun,[switch]$Force,[switch]$NoAgentSync,[switch]$Json,[switch]$NoAgentsMd)
$ErrorActionPreference = "Stop"; Set-StrictMode -Version Latest
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")

$srcSkills = Resolve-Path "$PSScriptRoot\..\.agents\skills" -EA Stop
$dstSkills = Join-Path (Get-GlobalConfigDir) "skills"
$srcScripts = Resolve-Path "$PSScriptRoot" -EA Stop
$dstScripts = Join-Path (Get-GlobalConfigDir) "scripts"
$globalDir = Get-GlobalConfigDir
$globalJsonc = Join-Path $globalDir "opencode.jsonc"
$globalJson  = Join-Path $globalDir "opencode.json"
# Prefer existing global config file — detect .json or .jsonc
if (Test-Path $globalJson) { $globalCfg = $globalJson }
elseif (Test-Path $globalJsonc) { $globalCfg = $globalJsonc }
else { $globalCfg = $globalJson }
$projectCfg = Resolve-Path "$PSScriptRoot\..\opencode.json" -EA Stop
$report = @{timestamp=(Get-Date -Format "o");steps=@{};errors=@();warnings=@()}

function Write-Step([string]$N,[scriptblock]$B) { if($DryRun){Write-Host "[dry-run] $N" -Fore Yellow;return}; Write-Host "==> $N" -Fore Cyan; try {&$B;$report.steps[$N]="ok"}catch{Write-Host "[err] $N : $_" -Fore Red;$report.errors+="$N : $_";$report.steps[$N]="fail"} }

# Step 1: Skill junctions
Write-Step "Skill junctions" {
    if (-not (Test-Path $dstSkills)) { New-Item -ItemType Directory -Path $dstSkills -Force | Out-Null }
    $count=0;$total=0; foreach ($skill in Get-ChildItem -Directory -Path $srcSkills) { $total++;$link=Join-Path $dstSkills $skill.Name; if(-not(Test-Path $link)){New-CrossPlatLink -Path $link -Target $skill.FullName;$count++} }
    Write-Host "  $count new junctions (total: $total)" -Fore Green; $report.steps["skill_junctions"]=@{created=$count;total=$total}
}

# Step 2: Scripts junction
Write-Step "Scripts junction" {
    if (-not (Test-Path $dstScripts)) { New-CrossPlatLink -Path $dstScripts -Target $srcScripts; Write-Host "  Created" -Fore Green } else { Write-Host "  Exists" -Fore Yellow }
}

# Step 2b: Commands sync (SSoT = repo commands/, hash-based — NOT copy-if-missing)
Write-Step "Commands sync" {
    $srcCommands = Resolve-Path "$PSScriptRoot\..\commands" -EA Stop
    $dstCommands = Join-Path (Get-GlobalConfigDir) "commands"
    if (-not (Test-Path $dstCommands)) { New-Item -ItemType Directory -Path $dstCommands -Force | Out-Null }
    $copied = 0; $upToDate = 0
    foreach ($f in Get-ChildItem -File -Path $srcCommands -Filter *.md) {
        $dst = Join-Path $dstCommands $f.Name
        if (Test-Path $dst) {
            $a = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
            $b = (Get-FileHash $dst -Algorithm SHA256).Hash
            if ($a -eq $b) { $upToDate++; continue }
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        $copied++
    }
    Write-Host "  $copied copied, $upToDate up-to-date" -Fore Green
    $report.steps["commands_sync"] = @{copied=$copied; up_to_date=$upToDate}
}

# Step 3: Global config (MCPs + permissions + agents)
Write-Step "Global config" {
    if ($Force -or -not (Test-Path $globalCfg)) {
        $existingAgents=@{}; if(Test-Path $globalCfg){try{$e=Get-Content $globalCfg -Raw|ConvertFrom-Json;if($e.PSObject.Properties.Match('agent').Count-gt 0){foreach($p in $e.agent.PSObject.Properties){$existingAgents[$p.Name]=$p.Value}}}catch{Write-Warning "  Could not read existing config"}}
        $cfg=@{'$schema'="https://opencode.ai/config.json";mcp=@{context7=@{enabled=$true;type="remote";url="https://mcp.context7.com/mcp"};engram=@{command=@("engram","mcp","--tools=mem_save,mem_search,mem_context,mem_session_summary,mem_get_observation,mem_save_prompt,mem_current_project,mem_judge");type="local"}};permission=@{bash=@{"*"="allow";"git commit *"="ask";"git push *"="ask";"git push --delete *"="ask";"git rebase *"="ask";"git reset *"="ask";"git merge *"="ask";"git branch -D *"="ask";"git stash drop *"="ask";"gh pr merge *"="ask";"git push --force *"="deny"};read=@{"*"="allow";"**/.env"="deny";"**/.env.*"="deny";"**/.env*"="deny";"**/credentials.json"="deny";"**/secrets/**"="deny";"**/*secret*"="deny";"**/.ssh/**"="deny";"**/*.key"="deny";"**/*.pem"="deny"}};agent=$existingAgents}
        # SEC-F2: port the project deny floor (scripts/opencode-config/shared-deny-rules.json)
        # into the global bash map so dangerous commands are denied even outside this repo.
        try {
            $denyFloorRaw = Get-Content (Join-Path $PSScriptRoot "opencode-config\shared-deny-rules.json") -Raw | ConvertFrom-Json
            $ported = 0
            foreach ($dp in $denyFloorRaw.PSObject.Properties) { $cfg.permission.bash[$dp.Name] = $dp.Value; $ported++ }
            Write-Host "  Ported $ported deny-floor rules (SEC-F2)" -Fore Green
        } catch { Write-Warning "  Could not read shared-deny-rules.json: $_" }
        if($cfg.agent.Keys.Count -eq 0){$cfg.agent=@{}}
        $cfg|ConvertTo-Json -Depth 10|Set-Content $globalCfg -Encoding UTF8 -Force
        Write-Host "  Written (preserved $($existingAgents.Keys.Count) agents)" -Fore Green
    } else { Write-Host "  Exists, skipping (-Force to overwrite)" -Fore Yellow }
}

# Step 4: Agent sync
if(-not $NoAgentSync){Write-Step "Agent sync" {
    if(-not(Test-Path $globalCfg)){throw "Global config not found -- run step 3 first"}
    try{$proj=Get-Content $projectCfg -Raw|ConvertFrom-Json;$glob=Get-Content $globalCfg -Raw|ConvertFrom-Json}catch{throw "Parse error: $_"}
    $agentNames=@($proj.agent.PSObject.Properties.Name | Where-Object { $_ -like 'gentleman-*' -or $_ -like 'gentle-*' -or $_ -like 'sdd-*' })
    if($glob.PSObject.Properties.Match('agent').Count-eq 0){$glob|Add-Member -Name agent -Value @{} -MemberType NoteProperty -Force}
    if($proj.PSObject.Properties.Match('agent').Count-eq 0){Write-Warning "  No project agents";$report.steps["agent_sync"]=@{added=0;note="no project agents"}}
    else{$added=0;$updated=0; foreach($n in $agentNames){$sp=$proj.agent.PSObject.Properties[$n]; if($null-eq$sp){continue};$gh=$glob.agent.PSObject.Properties.Match($n).Count-gt 0;$glob.agent|Add-Member -Name $n -Value $sp.Value -MemberType NoteProperty -Force;if($gh){$updated++}else{$added++}}
        if(-not$NoAgentsMd){$src=Join-Path (Split-Path $projectCfg -Parent) "AGENTS.md";$dst=Join-Path (Split-Path $globalCfg -Parent) "AGENTS.md";if(Test-Path $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination $dst -Force}}
        $glob|ConvertTo-Json -Depth 10|Set-Content $globalCfg -Encoding UTF8 -Force
        Write-Host "  ${added} added, ${updated} updated" -Fore Green;$report.steps["agent_sync"]=@{added=$added;updated=$updated}}
}}

# Step 5: Junction verification
Write-Step "Verify junctions" {
    $skills=Get-ChildItem $dstSkills -Directory -EA SilentlyContinue
    $bad=@($skills|Where-Object{$_ -is [System.IO.DirectoryInfo] -and $_.Target -and -not(Test-Path $_.Target)})
    if($bad.Count-gt 0){$bad|ForEach-Object{Write-Host "  [broken] $($_.Name)" -Fore Red};throw "$($bad.Count) broken junctions"}
    Write-Host "  Skills: $($skills.Count) valid | Scripts: $(Test-Path $dstScripts)" -Fore Green
}

# Step 6: MCP availability
Write-Step "MCP availability" {
    $engramPath=(Get-Command engram -EA SilentlyContinue).Source
    if($engramPath){Write-Host "  engram: $engramPath" -Fore Green;$report.steps["mcp_engram"]="found"}
    else{Write-Warning "  engram: not in PATH";$report.warnings+="engram not in PATH";$report.steps["mcp_engram"]="missing"}
    Write-Host "  context7: remote (verified at runtime)" -Fore Gray
}

# Report
$report.status=if($report.errors.Count-eq 0){"ok"}else{"fail"}
if($Json){$report|ConvertTo-Json -Depth 5}else{
    Write-Host "`n=== sync-global | Status: $($report.status) ===" -Fore $(if($report.errors.Count-eq 0){"Green"}else{"Red"})
    foreach($s in $report.steps.Keys){$v=$report.steps[$s];$c=if($v-eq"ok"-or($v-is[hashtable])){"Green"}else{"Red"};Write-Host "  $($s.PadRight(25)) $(if($v-is[string]){$v}else{'ok'})" -Fore $c}
    if($report.errors.Count-gt 0){Write-Host "  Errors: $($report.errors.Count)" -Fore Red;exit 1}
}
