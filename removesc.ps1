<#
.SYNOPSIS
    Language Sanitizer (removesc.ps1)
    Enforces a strict language policy: [English + Traditional Chinese (Rime) ONLY].
    Anything else (including Simplified Chinese) will be wiped.
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
# Standard Weasel TSF GUID
$WeaselGuid = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
# The InputMethodTip string for Traditional Chinese (0404)
$RimeTip    = "0404:$WeaselGuid"

# ==========================================
# [MAIN LOGIC]
# ==========================================
Write-Host "Starting Language Sanitization..." -ForegroundColor Cyan
Write-Host "Policy: Keep English & Traditional Chinese (Rime). Discard everything else."
Write-Host "------------------------------------------------"

try {
    # 1. Create a FRESH, EMPTY list
    $CleanList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]

    # 2. Get Current System List (Reference only)
    $CurrentList = Get-WinUserLanguageList
    
    # 3. HANDLE ENGLISH (Keep existing region preference if possible)
    $EnglishLang = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    
    if ($EnglishLang) {
        Write-Host " [KEEP] Found English: $($EnglishLang.LanguageTag)" -ForegroundColor Green
        $CleanList.Add($EnglishLang)
    } else {
        Write-Host " [ADD]  No English found. Adding default (en-US)" -ForegroundColor Yellow
        $DefaultEn = New-WinUserLanguageList "en-US"
        $CleanList.Add($DefaultEn[0])
    }

    # 4. HANDLE TRADITIONAL CHINESE (Reconstruct to ensure purity)
    Write-Host " [ADD]  Rebuilding Traditional Chinese (zh-TW)..." -ForegroundColor Green
    
    # Create a fresh object. This isolates us from any existing broken settings.
    $TwLangList = New-WinUserLanguageList "zh-TW"
    $TwLang = $TwLangList[0]

    # 5. INJECT RIME (If missing)
    # Note: New-WinUserLanguageList usually adds Microsoft Bopomofo by default. We append Rime.
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "      -> Injecting Rime Input Method..." -ForegroundColor Cyan
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "      -> Rime is already present." -ForegroundColor Gray
    }
    
    $CleanList.Add($TwLang)

    # 6. FORCE APPLY (THE PURGE)
    # This command overwrites the system list with our $CleanList.
    # Simplified Chinese (zh-CN) is NOT in $CleanList, so Windows will remove it.
    Write-Host "------------------------------------------------"
    Write-Host "Applying new configuration..." -ForegroundColor Yellow
    
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    
    Write-Host "SUCCESS: Language list reset." -ForegroundColor Green
    Write-Host "Check your taskbar now. Simplified Chinese should be gone."

} catch {
    Write-Host "------------------------------------------------"
    Write-Host "ERROR FAILED" -ForegroundColor Red
    Write-Host "Details: $_"
    Write-Host "------------------------------------------------"
    Write-Host "Tip: Close Windows 'Settings' window and try again."
}

# Cleanup temp
if (Test-Path "$env:TEMP\removesc_elevated.ps1") { Remove-Item "$env:TEMP\removesc_elevated.ps1" -ErrorAction SilentlyContinue }

Read-Host "Press Enter to exit..."

