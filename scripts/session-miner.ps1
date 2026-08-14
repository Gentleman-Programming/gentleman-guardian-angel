#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<# .SYNOPSIS Mine session histories for error patterns and propose corrections #>
param([ValidateSet('scan','apply','check','populate')][string]$Mode='scan',[switch]$Json,[switch]$Quiet,[int]$Threshold=2,[string[]]$PatternKeys,[string[]]$ErrorEntries,[string]$Root='')
if($Quiet){$Json=$true}
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if($Root){$rr=$Root}else{$rr=Split-Path -Parent $PSScriptRoot}
$cp=Join-Path $rr 'ANTI-PATTERN-CATALOG.md';$ld=Join-Path $rr '.learnings'
$ep=Join-Path $ld 'ERRORS.md';$lp=Join-Path $ld 'LEARNINGS.md'
$cachedLearnings=$null;$cachedErrors=$null
$ro='Multiline';try{
function rc{if(-not(Test-Path $cp)){return ,@()}
try{$c=Get-Content $cp -Raw}catch{Write-Debug "sm: cannot read catalog ($($_.Exception.Message))";return ,@()}
$p=@();$rows=[regex]::Matches($c,'^\|\s*\d+\s*\|.*?\|.*?\|.*?\|.*?\|.*?\|.*?\|',$ro)
foreach($r in $rows){$parts=$r.Value -split '\|' | ForEach-Object {$_.Trim()}
if($parts.Count-ge8){$id=0;if($parts[1]){[int]::TryParse($parts[1],[ref]$id) | Out-Null}
$p+=[PSCustomObject]@{Id=$id;Date=$parts[2];Pattern=$parts[3];Symptom=$parts[4];RootCause=$parts[5];Fix=$parts[6];Prevention=$parts[7]}}}
return ,$p}
function rl{if(-not(Test-Path $lp)){return ,@()}
$c = if($args[0]){$args[0]}else{try{Get-Content $lp -Raw}catch{Write-Debug "sm: cannot read learnings ($($_.Exception.Message))";return ,@()}}
$k=@();$m=[regex]::Matches($c,'^[\s]*Pattern-Key:\s*([^\n\r]+)',$ro)
foreach($x in $m){$k+=$x.Groups[1].Value.Trim()};return ,$k}
function re{if(-not(Test-Path $ep)){return ,@()}
$c = if($args[0]){$args[0]}else{try{Get-Content $ep -Raw}catch{Write-Debug "sm: cannot read errors ($($_.Exception.Message))";return ,@()}}
$e=@();$entries=[regex]::Matches($c,'^##\s+\[\w+-\d+-\d+\]\s+(.+?)$',$ro)
foreach($entry in $entries){$e+=$entry.Groups[1].Value.Trim()};return ,$e}
function frp{param([array]$cp,[array]$pk,[int]$mn)
$kc=@{};foreach($k in $pk){if($kc.ContainsKey($k)){$kc[$k]++}else{$kc[$k]=1}}
$r=@();foreach($e in $kc.GetEnumerator()){if($e.Value-ge$mn){$cat=$false
foreach($c in $cp){if($c.Pattern -cmatch [regex]::Escape($e.Name)){$cat=$true;break}}
$r+=[PSCustomObject]@{PatternKey=$e.Name;Count=$e.Value;Cataloged=$cat}}};return ,$r}
# --- Populate mode: inject session data into learnings/errors files ---
if($Mode-eq'populate'){
    $today=(Get-Date -Format 'yyyy-MM-dd')
    # Populate LEARNINGS.md with pattern keys
    $cachedLearnings = $null
    if($PatternKeys -and $PatternKeys.Count-gt0){
        $existingKeys=@();if(Test-Path $lp){$ec=Get-Content $lp -Raw;$cachedLearnings=$ec;$existingKeys=@([regex]::Matches($ec,'^[\s]*Pattern-Key:\s*([^\n\r]+)','Multiline')|ForEach-Object{$_.Groups[1].Value.Trim()})}
        $newLines=@();$todayKeys=@()
        foreach($pk in $PatternKeys){
            $key=$pk -replace '\s+','-' -replace '[^a-zA-Z0-9\-]','' -replace '-+','-' -replace '^-|-$',''
            if($key -and $key.Length-gt2 -and $existingKeys -notcontains $key -and $todayKeys -notcontains $key){
                $todayKeys+=$key;$newLines+="# $today`nPattern-Key: $key"
            }
        }
        if($newLines.Count-gt0){
            $nl="`r`n"+($newLines -join "`r`n")+"`r`n"
            Add-Content -Path $lp -Value $nl -Encoding UTF8
            if(-not $Json){Write-Host "  ⛏️  Populated $($newLines.Count) new pattern key(s) to LEARNINGS.md"}
        } elseif(-not $Json){Write-Host "  ⛏️  No new pattern keys to add (all exist or invalid)"}
    }
    # Populate ERRORS.md with error entries
    $cachedErrors = $null
    if($ErrorEntries -and $ErrorEntries.Count-gt0){
        $existingErrors=@();if(Test-Path $ep){$ec=Get-Content $ep -Raw;$cachedErrors=$ec;$existingErrors=@([regex]::Matches($ec,'^##\s+\[\w+-\d+-\d+\]\s+(.+?)$','Multiline')|ForEach-Object{$_.Groups[1].Value.Trim()})}
        $newErrors=@()
        foreach($ee in $ErrorEntries){
            $clean=$ee.Trim()
            if($clean -and $existingErrors -notcontains $clean){
                $newErrors+="## [$today] $clean"
            }
        }
        if($newErrors.Count-gt0){
            $nl="`r`n"+($newErrors -join "`r`n")+"`r`n"
            Add-Content -Path $ep -Value $nl -Encoding UTF8
            if(-not $Json){Write-Host "  ⛏️  Populated $($newErrors.Count) new error entry(ies) to ERRORS.md"}
        } elseif(-not $Json){Write-Host "  ⛏️  No new error entries to add (all exist or invalid)"}
    }
    # Fall through as check so caller gets repeated-pattern analysis
    # Invalidate cache so the check re-reads post-populate files from disk
    $cachedLearnings=$null;$cachedErrors=$null
    $Mode='check'
}
$catalog=rc;$patternKeys=rl $cachedLearnings;$errors=re $cachedErrors;$repeated=frp -cp $catalog -pk $patternKeys -mn $Threshold
if($Mode-eq'check'){$data=[PSCustomObject]@{CatalogEntries=@($catalog).Count;PatternKeys=@($patternKeys).Count;ErrorEntries=@($errors).Count;RepeatedPatterns=@($repeated).Count;Mode='check';Status=if(@($repeated).Count-gt0){'PATTERNS_FOUND'}else{'CLEAN'}}
if($Json){return($data | ConvertTo-Json)}
if(-not $Quiet){Write-Host "  Catalog: $(@($catalog).Count) entries`n  Patterns: $(@($patternKeys).Count) keys`n  Errors: $(@($errors).Count) entries`n  Repeated: $(@($repeated).Count) patterns`n  Status: $($data.Status)"};return}
if($Mode-eq'scan'){$uncataloged=@($repeated | Where-Object {-not $_.Cataloged})
# ponytail: cross-project wisdom cross-check
$wisdomPatterns=@();$wisdomDir=Join-Path (Join-Path (Join-Path $rr 'docs') 'cross-project') 'patterns'
if(Test-Path $wisdomDir){$wisdomFiles=Get-ChildItem $wisdomDir -Filter '*.json' -ErrorAction SilentlyContinue
foreach($wf in $wisdomFiles){try{$wp=Get-Content $wf.FullName -Raw|ConvertFrom-Json
$wpPattern=$wp.rule.summary
$wpTitle=$wp.title
if($wpPattern -or $wpTitle){$matched=$patternKeys|Where-Object{$_ -match [regex]::Escape(($wpPattern -replace '.{0,80}','')) -or $_ -cmatch $wpTitle}
if($matched){$wisdomPatterns+=[PSCustomObject]@{PatternId=$wp.id;Title=$wp.title;Severity=$wp.severity;Summary=$wp.rule.summary;MatchKey=$matched -join ',';File=$wf.Name}}}}
catch{Write-Debug "sm: wisdom cross-check skip $($wf.Name)"}}}
$data=[PSCustomObject]@{CatalogCount=@($catalog).Count;PatternKeyCount=@($patternKeys).Count;ErrorCount=@($errors).Count;RepeatedPatterns=$repeated;UnCatalogedCount=$uncataloged.Count;CanApply=$uncataloged.Count-gt0;WisdomMatchCount=@($wisdomPatterns).Count;WisdomMatches=$wisdomPatterns}
if($Json){return($data | ConvertTo-Json -Depth 3)}
if(-not $Quiet){Write-Host "Catalog: $($catalog.Count) anti-patterns cataloged`nPattern keys: $($patternKeys.Count) from learnings`nErrors: $($errors.Count) entries"}
if($repeated.Count-eq0){if(-not $Quiet){Write-Host "[OK] No repeated patterns found (threshold: $Threshold)"};return}
if(-not $Quiet){Write-Host '[WARN] Repeated patterns detected:'};foreach($r in $repeated){$s=if($r.Cataloged){'[cataloged]'}else{'[uncataloged]'};if(-not $Quiet){Write-Host "  [$($r.Count)x] $($r.PatternKey) -- $s"}}
if($uncataloged.Count-gt0){if(-not $Quiet){Write-Host "Proposal: run with -Mode apply to add $($uncataloged.Count) new anti-pattern(s)"}};return}
if($Mode-eq'apply'){$uncataloged=@($repeated | Where-Object {-not $_.Cataloged})
if($uncataloged.Count-eq0){if(-not $Quiet){Write-Host '[OK] Nothing to apply'};return}
if(-not $Quiet){Write-Host "Would add $($uncataloged.Count) new anti-pattern(s):"};foreach($u in $uncataloged){$sk=$u.PatternKey -replace '[^\w-]','_';if(-not $Quiet){Write-Host "  - [$($u.Count)x] $($u.PatternKey) -> ANTI-PATTERN-CATALOG.md + docs/anti-patterns/$sk.md"}}
if(-not $Quiet){Write-Host 'Run manually: edit ANTI-PATTERN-CATALOG.md with pattern details'}}
}finally{$catalog=$patternKeys=$errors=$repeated=$data=$uncataloged=$null} # ponytail: removed explicit GC.Collect — let .NET handle it
