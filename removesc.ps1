<#
.SYNOPSIS
    Language Sanitizer (Array Version)
    Fixes "Type not found" error by using standard arrays.
#>

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\removesc_elevated.ps1"
    $MyInvocation.MyCommand.ScriptBlock | Out-File $TempScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [CONFIGURATION]
# ==========================================
$WeaselGuid = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$RimeTip    = "0404:$WeaselGuid"

# ==========================================
# [MAIN LOGIC]
# ==========================================
Write-Host "Starting Language Sanitization (Simple Mode)..." -ForegroundColor Cyan
Write-Host "Policy: Keep English & Traditional Chinese (Rime). Discard everything else."
Write-Host "------------------------------------------------"

try {
    # 1. Initialize a simple empty Array (Fixed the "Type not found" error)
    $CleanList = @()

    # 2. Get Current System List
    $CurrentList = Get-WinUserLanguageList
    
    # 3. HANDLE ENGLISH
    $EnglishLang = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    
    if ($EnglishLang) {
        Write-Host " [KEEP] Found English: $($EnglishLang.LanguageTag)" -ForegroundColor Green
        $CleanList += $EnglishLang
    } else {
        Write-Host " [ADD]  No English found. Adding default (en-US)" -ForegroundColor Yellow
        $DefaultEn = New-WinUserLanguageList "en-US"
        $CleanList += $DefaultEn[0]
    }

    # 4. HANDLE TRADITIONAL CHINESE
    Write-Host " [ADD]  Rebuilding Traditional Chinese (zh-TW)..." -ForegroundColor Green
    
    # Create fresh object
    $TwLangList = New-WinUserLanguageList "zh-TW"
    $TwLang = $TwLangList[0]

    # 5. INJECT RIME
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "      -> Injecting Rime Input Method..." -ForegroundColor Cyan
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "      -> Rime is already present." -ForegroundColor Gray
    }
    
    $CleanList += $TwLang

    # 6. FORCE APPLY
    Write-Host "------------------------------------------------"
    Write-Host "Applying new configuration..." -ForegroundColor Yellow
    
    # PowerShell will automatically convert our array to the required List type
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    
    Write-Host "SUCCESS: Language list reset." -ForegroundColor Green
    Write-Host "Simplified Chinese should be gone."

} catch {
    Write-Host "------------------------------------------------"
    Write-Host "ERROR FAILED" -ForegroundColor Red
    Write-Host "Details: $_"
    Write-Host "------------------------------------------------"
}

# Cleanup
if (Test-Path "$env:TEMP\removesc_elevated.ps1") { Remove-Item "$env:TEMP\removesc_elevated.ps1" -ErrorAction SilentlyContinue }

Read-Host "Press Enter to exit..."
