<#
.SYNOPSIS
    Rime Uninstaller (Winget Only)

2601172825
#>

# ==========================================
# [CONFIGURATION]
# ==========================================
# Update this URL to match your repo structure
$ScriptUrl = "https://perrier8wu.github.io/rime-win11-deploy/uninstall.ps1"

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Admin privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_uninstall_elevated.ps1"
    try { Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript }
    catch { Write-Error "Download failed."; Start-Sleep 5; Exit }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [WINGET UNINSTALLATION]
# ==========================================
$ErrorActionPreference = "Continue"
Write-Host "Starting Winget Uninstallation..." -ForegroundColor Cyan

# 1. Kill Processes (Safety measure)
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

# 2. Run Winget
# -h : Silent mode
# --accept-source-agreements : Bypass agreements prompt
Write-Host "Executing: winget uninstall Rime.Weasel..."
try {
    winget uninstall --id Rime.Weasel -h --accept-source-agreements
} catch {
    Write-Error "Winget failed to uninstall Rime. Please check if it's installed."
}

# ==========================================
# [CLEANUP RESIDUE]
# ==========================================
Write-Host "Cleaning up residual files..."

# 1. User Data (AppData) - Wipe it for a clean slate
$UserDataDir = "$env:APPDATA\Rime"
if (Test-Path $UserDataDir) {
    Write-Host "Removing User Data: $UserDataDir"
    Remove-Item -Path $UserDataDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 2. Program Files (If Winget left anything behind)
$ProgDir = "C:\Program Files\Rime"
if (Test-Path $ProgDir) {
    Write-Host "Removing Program Dir: $ProgDir"
    Remove-Item -Path $ProgDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Cleanup temp script
Remove-Item "$env:TEMP\rime_uninstall_elevated.ps1" -ErrorAction SilentlyContinue

Write-Host "`nUninstallation Complete." -ForegroundColor Green
Read-Host "Press Enter to exit..."

