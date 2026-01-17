<#
.SYNOPSIS
    Rime Uninstaller (Winget + Registry/IME Cleanup)
#>

# ==========================================
# [CONFIGURATION]
# ==========================================
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
# [STEP 1: UNINSTALLATION]
# ==========================================
$ErrorActionPreference = "Continue"
Write-Host "Starting Uninstallation..." -ForegroundColor Cyan

Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

Write-Host "Executing Winget Uninstall..."
try {
    winget uninstall --id Rime.Weasel -h --accept-source-agreements
} catch {
    Write-Warning "Winget uninstall failed or app already removed."
}

# ==========================================
# [STEP 2: CLEANUP FILES]
# ==========================================
Write-Host "Cleaning up files..."

# User Data
$UserDataDir = "$env:APPDATA\Rime"
if (Test-Path $UserDataDir) {
    Remove-Item -Path $UserDataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed: $UserDataDir"
}

# Program Files
$ProgDir = "C:\Program Files\Rime"
if (Test-Path $ProgDir) {
    Remove-Item -Path $ProgDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed: $ProgDir"
}

# ==========================================
# [STEP 3: REMOVE PHANTOM INPUT METHOD]
# ==========================================
# This is the critical fix for the "Win+Space" issue
Write-Host "Cleaning up Windows Input Method List..."

try {
    # Get current list
    $LangList = Get-WinUserLanguageList
    $Modified = $false

    foreach ($Lang in $LangList) {
        # Check for Weasel GUID (Standard: {A3F61664-90B7-4EA0-86FA-5056747127C7})
        if ($Lang.InputMethodTips -match "A3F61664") {
            Write-Host " - Removing Weasel from $($Lang.LanguageTag)..."
            $Lang.InputMethodTips = $Lang.InputMethodTips | Where-Object { $_ -notmatch "A3F61664" }
            $Modified = $true
        }
    }

    if ($Modified) {
        Set-WinUserLanguageList $LangList -Force
        Write-Host "Input Method List refreshed." -ForegroundColor Green
    } else {
        Write-Host "No phantom entries found."
    }
} catch {
    Write-Warning "Failed to clean Input Method list. You may need to remove it manually in Settings."
}

# Cleanup temp script
Remove-Item "$env:TEMP\rime_uninstall_elevated.ps1" -ErrorAction SilentlyContinue

Write-Host "`nUninstallation Complete." -ForegroundColor Green
Read-Host "Press Enter to exit..."
