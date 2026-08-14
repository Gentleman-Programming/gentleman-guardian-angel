#requires -Version 5.1
<# .SYNOPSIS System.Text.Json helper — fast JSON, bypasses cmdlet overhead #>
if(-not('System.Text.Json.JsonSerializer' -as [type])){Add-Type -AssemblyName System.Text.Json}
function ConvertTo-JsonFast{
  [CmdletBinding()]param($Object,[switch]$Pretty)
  $o=[System.Text.Json.JsonSerializerOptions]::new()
  $o.WriteIndented=$Pretty;$o.MaxDepth=100
  $in=ConvertTo-JsonNormalized $Object
  if($null -eq $in){return 'null'}
  [System.Text.Json.JsonSerializer]::Serialize($in,$in.GetType(),$o)
}
function ConvertTo-JsonNormalized{
  param($InputObject)
  if($null -eq $InputObject){return $null}
  if($InputObject -is [System.Management.Automation.PSObject]){
    $h=@{};foreach($p in $InputObject.PSObject.Properties){$h[$p.Name]=(ConvertTo-JsonNormalized $p.Value)}
    return $h
  }
  if($InputObject -is [System.Collections.IDictionary]){return $InputObject}
  if($InputObject -is [Collections.IEnumerable]-and$InputObject -isnot [string]){
    $result=@();foreach($item in $InputObject){$result+=(ConvertTo-JsonNormalized $item)}
    return $result
  }
  $InputObject
}
Export-ModuleMember -Function ConvertTo-JsonFast
