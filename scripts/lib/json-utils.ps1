#requires -Version 7

function Get-DeepClone {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    $serial = [System.Management.Automation.PSSerializer]::Serialize($InputObject)
    [System.Management.Automation.PSSerializer]::Deserialize($serial)
}

function ConvertTo-JsonSafe {
    param($InputObject, [int]$Depth = 10)
    if ($null -eq $InputObject) { return 'null' }
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    # Fix single-element array unwrapping: "paths": ".x" → "paths": [".x"]
    $json = [regex]::Replace($json, '"paths"\s*:\s*"([^"]+)"', '"paths": ["$1"]')
    $json
}

