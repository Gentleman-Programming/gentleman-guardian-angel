@echo off
REM sync-all.bat — CMD-compatible wrapper for sync-all.ps1
REM Finds pwsh.exe (PowerShell 7+) and invokes the script.
REM
REM Usage:
REM   sync-all            — full sync
REM   sync-all -Json      — JSON output for agent consumption
REM   sync-all -Quiet     — minimal output

where pwsh.exe >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] PowerShell 7+ (pwsh.exe) not found.
    echo.
    echo   Install via: winget install Microsoft.PowerShell
    echo   Or download: https://github.com/PowerShell/PowerShell/releases
    echo.
    pause
    exit /b 1
)

pwsh.exe -NoLogo -NoProfile -File "%~dp0sync-all.ps1" %*
exit /b %ERRORLEVEL%
