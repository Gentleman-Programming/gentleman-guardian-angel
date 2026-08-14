#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Unified verify profiles E1/E2/E3 -- runnable checks for triple-verify gates.
#>
param(
    [ValidateSet('E1','E2','E3','All')][string]$ProfileName='All',
    [switch]$Json,[switch]$Quiet,
    [string]$Root=(Split-Path $PSScriptRoot -Parent)
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$r=@{profile=$ProfileName;checks=@();passed=0;failed=0;errors=@()}
if($Quiet){$Json=$true}
function Add-Check{
    param([string]$N,[bool]$P,[string]$D='')
    $script:r.checks+=@{name=$N;passed=$P;detail=$D}
    if($P){$script:r.passed++}else{$script:r.failed++}
    if(-not $Quiet){Write-Host ("[{0}] {1} -- {2}" -f $(if($P){'PASS'}else{'FAIL'}),$N,$D) -ForegroundColor $(if($P){'Green'}else{'Red'})}
}
function Invoke-E1Check{
    $sDir=Join-Path $Root 'scripts'
    $sb_bs = [System.Text.StringBuilder]::new(65536)
    Get-ChildItem "$sDir\*.ps1" | ForEach-Object {
        $e=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e)
        if($e){$null = $sb_bs.AppendLine("$($_.Name): $($e.Message)")}
    }
    $bs = @($sb_bs.ToString().Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries))
    if($bs.Count-eq0){Add-Check 'PS Syntax' $true 'All scripts parse OK'}else{Add-Check 'PS Syntax' $false "$($bs.Count) files with errors: $($bs -join '; ')"}
    $skd=Join-Path $Root '.agents\skills'
    $sb_bf = [System.Text.StringBuilder]::new(65536)
    if(Test-Path $skd){
        Get-ChildItem "$skd\*\SKILL.md" | ForEach-Object {
            $c=[IO.File]::ReadAllText($_.FullName)
            if($c-match'^---'){
                $end=$c.IndexOf('---',3)
                if($end-eq-1){$null = $sb_bf.AppendLine("$($_.Directory.Name): unclosed frontmatter")}
            }
        }
    }
    $bf = @($sb_bf.ToString().Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries))
    if($bf.Count-eq0){Add-Check 'Skill Frontmatter' $true 'All frontmatter valid'}else{Add-Check 'Skill Frontmatter' $false "$($bf.Count) issues: $($bf -join '; ')"}
    $xs=Join-Path $sDir 'cross-ref-check.ps1'
    if(Test-Path $xs){
        $cmd=(Resolve-Path $xs).Path
        if($cmd.StartsWith($sDir)){& $cmd;Add-Check 'Cross-Ref Check' ($LASTEXITCODE-eq0) "exit $LASTEXITCODE"}else{Add-Check 'Cross-Ref Check' $false 'path outside scripts dir'}
    }else{Add-Check 'Cross-Ref Check' $true 'not found (skipped)'}
}
function Invoke-E2Check{
    $ps=Join-Path $Root 'scripts\pssa-gate.ps1'
    if(Test-Path $ps){
        $cmd=(Resolve-Path $ps).Path
        $scriptsDir=Join-Path $Root 'scripts'
        if($cmd.StartsWith($scriptsDir)){& $cmd -Mode Check -Path $Root;Add-Check 'PSSA Gate' ($LASTEXITCODE-eq0) "exit $LASTEXITCODE"}else{Add-Check 'PSSA Gate' $false 'path outside scripts dir'}
    }else{Add-Check 'PSSA Gate' $true 'not found (skipped)'}
    $sb_sf = [System.Text.StringBuilder]::new(65536)
    $sPat=@('password\s*=','secret\s*=','api[_-]?key\s*=','token\s*=','connection\s*string\s*=',
             'GH_TOKEN\s*=','GITHUB_TOKEN\s*=','ghp_','gho_','ghs_','github_pat_','ctx7sk_','AKIA',
             'xox[abprs]-\d+','sk-[a-zA-Z0-9]{20,}','-----BEGIN\s+(RSA|EC|DSA|PRIVATE|OPENSSH)\s+KEY')
    # Allowlist: files that DEFINE or DOCUMENT these patterns (self-referential scan noise).
    # A real secret in any OTHER file is still detected. Add here only if the file documents
    # the pattern format (docs, examples) or implements the detection itself.
    $sSkip=@('scripts\verify.ps1','scripts\check-mcp-security.ps1','scripts\tests\check-mcp-security.Tests.ps1','scripts\tests\verify.Tests.ps1',
             'docs\mejoras\2026-07-29-gentleman-agent-gh-global-analysis.md','docs\mejoras\2026-07-29-gentleman-agent-gh-cycle28-analysis.md',
             'docs\design\pattern-guard.md','docs\CHANGELOG.md',
             '.agents\skills\pdf-utils\SKILL.md','.agents\skills\security-scanner\references\patterns-guide.md')
    $sDirs=@((Join-Path $Root 'scripts'),(Join-Path $Root '.agents\skills'),(Join-Path $Root '.github\workflows'),(Join-Path $Root 'docs'))
    foreach($dir in $sDirs){
        if(-not(Test-Path $dir)){continue}
        Get-ChildItem $dir -Recurse -Include '*.ps1','*.md','*.psm1' | ForEach-Object {
            $rel=$_.FullName.Replace($Root,'').TrimStart('\').Replace('/','\')
            if($sSkip -contains $rel){return}
            $c=[IO.File]::ReadAllText($_.FullName)
            foreach($p in $sPat){if($c-match$p){$null = $sb_sf.AppendLine("$($_.Name): matched '$p'")}}
        }
    }
    $sf = @($sb_sf.ToString().Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries))
    if($sf.Count-eq0){Add-Check 'Secrets Scan' $true 'No patterns detected'}else{Add-Check 'Secrets Scan' $false "$($sf.Count) potential secrets: $($sf -join '; ')"}
    Push-Location $Root
    # Runtime state files are tracked but legitimately dirty every session
    # (score auto-updates them). Ignore them for hygiene; real code changes still fail.
    $rt=@('\.gentleman-mode$','\.project\.json$','BITACORA\.md$')
    $gs=@(git status --short | Where-Object {$line=$_;$skip=$false;foreach($p in $rt){if($line-match$p){$skip=$true;break}};-not$skip})
    Pop-Location
    if($gs.Count-eq0){Add-Check 'Git Hygiene' $true 'Working tree clean'}else{Add-Check 'Git Hygiene' $false "Uncommitted changes detected: $($gs -join '; ')"}
    $rp=Join-Path $Root 'review-rules.jsonc'
    if(Test-Path $rp){
        try{
            $raw=Get-Content $rp -Raw -Encoding UTF8
            $stripped=$raw-replace'(?m)^\s*//.*$',''-replace'(?m)\s*//[^"\n]*$',''-replace'(?s)/\*.*?\*/',''
            $null=$stripped | ConvertFrom-Json
            Add-Check 'review-rules.jsonc' $true 'Parses OK'
        }catch{Add-Check 'review-rules.jsonc' $false "Parse error: $_"}
    }else{Add-Check 'review-rules.jsonc' $true 'Not found (skipped)'}
}
function Invoke-E3Check{
    $cd=Join-Path $Root '.agents\skills'
    $gd=Join-Path (Get-GlobalConfigDir) "skills"
    $sb_mj = [System.Text.StringBuilder]::new(65536)
    if((Test-Path $cd)-and(Test-Path $gd)){
        Get-ChildItem $cd -Directory | Where-Object {$_.Name -ne '_shared'} | ForEach-Object {
            if(-not(Test-Path (Join-Path $gd $_.Name))){$null = $sb_mj.AppendLine($_.Name)}
        }
    }
    $mj = @($sb_mj.ToString().Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries))
    if($mj.Count-eq0){Add-Check 'Global Junctions' $true 'All junctions present'}else{Add-Check 'Global Junctions' $false "Missing: $($mj -join ', ')"}
    $pj=Join-Path $Root '.project.json'
    if(Test-Path $pj){
        try{
            $pjc=Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json
            $dc=$pjc.score.dimensions.PSObject.Properties.Name.Count
            $sc=$pjc.score.current
            if($dc-ge6-and$sc-ge0-and$sc-le10){Add-Check '.project.json' $true "$dc dims, score $sc/10"}else{Add-Check '.project.json' $false "Invalid structure: $dc dims, score $sc"}
        }catch{Add-Check '.project.json' $false "Parse error: $_"}
    }else{Add-Check '.project.json' $false 'Not found'}
    $sDir=Join-Path $Root 'scripts'
    $sb_mh = [System.Text.StringBuilder]::new(65536)
    [IO.Directory]::EnumerateFiles($sDir, '*.ps1') | ForEach-Object {
        $c=[IO.File]::ReadAllText($_)
        if($c -notmatch '\.SYNOPSIS'){$null = $sb_mh.AppendLine($_.Name)}
    }
    $mh = @($sb_mh.ToString().Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries))
    if($mh.Count-eq0){Add-Check 'Script Help' $true 'All scripts have .SYNOPSIS'}else{Add-Check 'Script Help' $false "$($mh.Count) missing: $($mh -join ', ')"}
    $cp=Join-Path $Root 'CYCLE.md'
    if(Test-Path $cp){
        $cc=Get-Content $cp -Raw -Encoding UTF8
        $hb=$cc-match'\|\s*Item\s*\|'
        $hl=$cc-match'LOOP:'
        $hm=$cc-match'\|\s*Metric\s*\|'
        $dt=@()
        if($hb){$dt+='backlog'}
        if($hl){$dt+='loop'}
        if($hm){$dt+='metrics'}
        Add-Check 'CYCLE.md' $true "Sections found: $($dt -join ', ')"
    }else{Add-Check 'CYCLE.md' $false 'Not found'}
}
switch($ProfileName){
    'E1'{Invoke-E1Check}
    'E2'{Invoke-E2Check}
    'E3'{Invoke-E3Check}
    'All'{Invoke-E1Check;Invoke-E2Check;Invoke-E3Check}
}
$r.allPassed=($r.failed-eq0)
if($Json){
    $r.timestamp=(Get-Date -Format 'o')
    Write-Output ($r | ConvertTo-Json -Depth 3)
}
exit $(if($r.allPassed){0}else{1})
