<#
.SYNOPSIS
    addRime.ps1 - Rime Injection Diagnostic Tool
    Focus: Add Rime to zh-TW and Remove Microsoft Bopomofo.
#>

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\addrime_elevated.ps1"
    $MyInvocation.MyCommand.ScriptBlock | Out-File $TempScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [DIAGNOSTIC CONFIG]
# ==========================================
$WeaselPath     = "C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe"
# Standard Weasel CLSID (The ID used in Registry)
$WeaselClsid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
# Microsoft Bopomofo GUID (To remove)
$BopomofoGuid   = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: REGISTRY CHECK]
# ==========================================
Write-Host "--- STEP 1: Checking System Registry ---" -ForegroundColor Cyan
$RegPath = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselClsid"

if (Test-Path $RegPath) {
    Write-Host "[OK] Weasel is registered in System Registry." -ForegroundColor Green
    # Get the LanguageProfile (to confirm it supports 0x0404 zh-TW)
    $ProfilePath = "$RegPath\LanguageProfile\0x00000404\$WeaselClsid"
    if (Test-Path $ProfilePath) {
        Write-Host "[OK] Weasel has a valid Traditional Chinese (0404) profile." -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Weasel Registry exists but 0404 Profile is missing." -ForegroundColor Red
        Write-Host "Attempting to fix by running '/install'..."
        Start-Process $WeaselPath -ArgumentList "/install" -Wait
    }
} else {
    Write-Host "[FAIL] Weasel is NOT in the Registry." -ForegroundColor Red
    if (Test-Path $WeaselPath) {
        Write-Host "Running WeaselDeployer /install to register it..."
        Start-Process $WeaselPath -ArgumentList "/install" -Wait
        Start-Sleep -Seconds 2
        if (Test-Path $RegPath) { Write-Host "[FIXED] Registration successful." -ForegroundColor Green }
        else { Write-Error "Failed to register Weasel. Windows will REFUSE to add it."; Pause; Exit }
    } else {
        Write-Error "WeaselDeployer not found at $WeaselPath"; Pause; Exit
    }
}

# ==========================================
# [STEP 2: CONSTRUCT TIP STRING]
# ==========================================
Write-Host "`n--- STEP 2: Constructing Input Method String ---" -ForegroundColor Cyan
# TSF TIP Format: LangID:CLSID{ProfileGUID}
# For Weasel, CLSID and ProfileGUID are usually the same.
$RimeTip = "0404:$WeaselClsid$WeaselClsid"
Write-Host "Target String: $RimeTip"

# ==========================================
# [STEP 3: MODIFY LANGUAGE LIST]
# ==========================================
Write-Host "`n--- STEP 3: Modifying Language List ---" -ForegroundColor Cyan

try {
    # 1. Get Current List
    $CurrentList = Get-WinUserLanguageList
    $TwLang = $null

    # 2. Find or Create zh-TW
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if (-not $TwLang) {
        Write-Host "zh-TW not found. Creating new..."
        $TwLang = (New-WinUserLanguageList "zh-TW")[0]
        $CurrentList.Add($TwLang)
    } else {
        Write-Host "Found existing zh-TW."
    }

    # 3. ADD RIME
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "Adding Rime..."
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "Rime is already in the list object."
    }

    # 4. REMOVE BOPOMOFO
    $BopomofoTip = "0404:$BopomofoGuid"
    if ($TwLang.InputMethodTips -contains $BopomofoTip) {
        Write-Host "Removing Microsoft Bopomofo..."
        $TwLang.InputMethodTips.Remove($BopomofoTip)
    } else {
        Write-Host "Microsoft Bopomofo not found in list."
    }

    # 5. VERIFY BEFORE APPLY
    Write-Host "`nCurrent Inputs in zh-TW object:" -ForegroundColor Gray
    $TwLang.InputMethodTips | ForEach-Object { Write-Host " - $_" }

    if ($TwLang.InputMethodTips.Count -eq 0) {
        Write-Error "ABORTING: The list is empty! Windows will reject this."
        Pause; Exit
    }

    # 6. APPLY
    Write-Host "`nApplying settings to Windows..." -ForegroundColor Yellow
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    
    Write-Host "[SUCCESS] Settings applied." -ForegroundColor Green

    # 7. FINAL VERIFICATION
    Start-Sleep -Seconds 1
    $FinalList = Get-WinUserLanguageList
    $FinalTw = $FinalList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    if ($FinalTw.InputMethodTips -contains $RimeTip) {
        Write-Host "VERIFIED: Rime is effectively active!" -ForegroundColor Green
    } else {
        Write-Host "FAILURE: Windows silently discarded Rime." -ForegroundColor Red
        Write-Host "This usually means the GUID $WeaselClsid is considered invalid by TSF."
    }

} catch {
    Write-Error "Error: $_"
}

# Cleanup
if (Test-Path "$env:TEMP\addrime_elevated.ps1") { Remove-Item "$env:TEMP\addrime_elevated.ps1" -ErrorAction SilentlyContinue }

Write-Host "`nDone."
Read-Host "Press Enter to exit..."

