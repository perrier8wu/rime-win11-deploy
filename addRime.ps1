<#
.SYNOPSIS
    addRime.ps1 (V3) - Direct Registry Patch
    Bypasses WeaselDeployer and manually writes TSF Registry Keys.
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
# [CONFIG]
# ==========================================
# IMPORTANT: Verify this path matches your installation
$WeaselVersion  = "0.17.4"
$WeaselDir      = "C:\Program Files\Rime\weasel-$WeaselVersion"
$WeaselDll      = "$WeaselDir\Weasel.dll"
$WeaselClsid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$BopomofoGuid   = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: MANUAL REGISTRY INJECTION]
# ==========================================
Write-Host "--- STEP 1: Manual Registry Injection ---" -ForegroundColor Cyan

if (-not (Test-Path $WeaselDll)) {
    Write-Error "CRITICAL: Weasel.dll not found at $WeaselDll"
    Write-Error "Cannot register. Please check the folder path."
    Pause; Exit
}

$TipRoot = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselClsid"
$LangKey = "$TipRoot\LanguageProfile\0x00000404\$WeaselClsid"
$CatKey  = "$TipRoot\Category\Category\{534C48C1-0607-4098-A521-4FC6051500F9}"

try {
    Write-Host "Writing TSF Keys directly to Registry..."

    # 1. Root TIP Key
    if (!(Test-Path $TipRoot)) { New-Item -Path $TipRoot -Force | Out-Null }
    Set-ItemProperty -Path $TipRoot -Name "Description" -Value "Rime" -Force
    Set-ItemProperty -Path $TipRoot -Name "Display Description" -Value "@$WeaselDll,-1" -Force
    Set-ItemProperty -Path $TipRoot -Name "Icon" -Value "$WeaselDll,0" -Force
    Set-ItemProperty -Path $TipRoot -Name "Enable" -Value 1 -Type DWord -Force

    # 2. Language Profile (zh-TW 0x0404)
    if (!(Test-Path $LangKey)) { New-Item -Path $LangKey -Force | Out-Null }
    Set-ItemProperty -Path $LangKey -Name "Description" -Value "Rime" -Force
    Set-ItemProperty -Path $LangKey -Name "Icon" -Value "$WeaselDll,0" -Force
    Set-ItemProperty -Path $LangKey -Name "Enable" -Value 1 -Type DWord -Force

    # 3. Category (Keyboard Category)
    if (!(Test-Path $CatKey)) { New-Item -Path $CatKey -Force | Out-Null }

    Write-Host "[SUCCESS] Registry keys written successfully." -ForegroundColor Green
} catch {
    Write-Error "Registry Write Failed: $_"
    Pause; Exit
}

# ==========================================
# [STEP 2: ADD RIME & REMOVE BOPOMOFO]
# ==========================================
Write-Host "`n--- STEP 2: Updating Language List ---" -ForegroundColor Cyan

try {
    $RimeTip = "0404:$WeaselClsid$WeaselClsid"
    $BopomofoTip = "0404:$BopomofoGuid"
    
    $CurrentList = Get-WinUserLanguageList
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if (-not $TwLang) {
        Write-Host "Creating zh-TW..."
        $TwLang = (New-WinUserLanguageList "zh-TW")[0]
        $CurrentList.Add($TwLang)
    }

    # Add Rime
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "Injecting Rime (forced)..."
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "Rime already in list."
    }

    # Remove Bopomofo
    if ($TwLang.InputMethodTips -contains $BopomofoTip) {
        Write-Host "Removing Microsoft Bopomofo..."
        $TwLang.InputMethodTips.Remove($BopomofoTip)
    }

    # Apply
    Write-Host "Applying settings..."
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Language list updated." -ForegroundColor Green
    
    # Verify
    Start-Sleep -Seconds 1
    $VerifyList = Get-WinUserLanguageList
    $VerifyTw = $VerifyList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($VerifyTw.InputMethodTips -contains $RimeTip) {
        Write-Host "VERIFIED: Rime is active!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Rime failed to stick. Restart might be required." -ForegroundColor Red
    }

} catch {
    Write-Error "Error: $_"
}

# Cleanup
if (Test-Path "$env:TEMP\addrime_elevated.ps1") { Remove-Item "$env:TEMP\addrime_elevated.ps1" -ErrorAction SilentlyContinue }

Write-Host "`nDone."
Read-Host "Press Enter to exit..."
#V3

