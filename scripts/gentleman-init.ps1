#requires -Version 7

<#
.SYNOPSIS
    Gentleman-ize a project — alias for use-gentleman.ps1.

.DESCRIPTION
    Bootstraps a project's opencode.json from the SSoT chain
    (opencode-base.json + permission-templates.json) with .gentleman-mode='manual'.
    This is the preferred entry point; forwards all arguments to use-gentleman.ps1.

.EXAMPLE
    gentleman-init
    .\scripts\gentleman-init.ps1
    gentleman-init -TargetDir ..\my-api -DefaultAgent gentleman-quick -Json -Yes
#>
& (Join-Path $PSScriptRoot 'use-gentleman.ps1') @args

