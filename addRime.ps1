<#
.SYNOPSIS
    addRime.ps1 (User-Level Force Activate)
    Syncs HKLM registry to HKCU and modifies Input Method List.
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
# Weasel GUID (CLSID)
$WeaselGuid     = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
# Microsoft Bopomofo GUID
$MsBopomofoGuid = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: SYNC REGISTRY (HKLM -> HKCU)]
# ==========================================
Write-Host "--- STEP 1: Syncing Registry to Current User ---" -ForegroundColor Cyan

# Source (System)
$HklmPath = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselGuid"
$HklmLang = "$HklmPath\LanguageProfile\0x00000404\$WeaselGuid"

# Destination (User)
$HkcuPath = "HKCU:\SOFTWARE\Microsoft\CTF\TIP\$WeaselGuid"
$HkcuLang = "$HkcuPath\LanguageProfile\0x00000404\$WeaselGuid"

if (Test-Path $HklmPath) {
    Write-Host "Found valid System Registration."
    
    # 1. Create User Keys
    if (-not (Test-Path $HkcuPath)) { New-Item -Path $HkcuPath -Force | Out-Null }
    if (-not (Test-Path $HkcuLang)) { New-Item -Path $HkcuLang -Force | Out-Null }

    # 2. Copy properties (Description, Icon, Enable)
    try {
        # Copy Root properties
        Get-ItemProperty -Path $HklmPath | ForEach-Object {
            if ($_.PSObject.Properties["Description"]) { Set-ItemProperty -Path $HkcuPath -Name "Description" -Value $_.Description -Force }
            if ($_.PSObject.Properties["Icon"]) { Set-ItemProperty -Path $HkcuPath -Name "Icon" -Value $_.Icon -Force }
            if ($_.PSObject.Properties["Display Description"]) { Set-ItemProperty -Path $HkcuPath -Name "Display Description" -Value $_."Display Description" -Force }
            Set-ItemProperty -Path $HkcuPath -Name "Enable" -Value 1 -Type DWord -Force
        }

        # Copy LanguageProfile properties
        Get-ItemProperty -Path $HklmLang | ForEach-Object {
            if ($_.PSObject.Properties["Description"]) { Set-ItemProperty -Path $HkcuLang -Name "Description" -Value $_.Description -Force }
            if ($_.PSObject.Properties["Icon"]) { Set-ItemProperty -Path $HkcuLang -Name "Icon" -Value $_.Icon -Force }
            Set-ItemProperty -Path $HkcuLang -Name "Enable" -Value 1 -Type DWord -Force
        }
        Write-Host "[SUCCESS] Synced settings to HKCU." -ForegroundColor Green
    } catch {
        Write-Warning "Sync warning: $_"
    }
} else {
    Write-Error "CRITICAL: HKLM Registry Key missing! Cannot sync."
    Pause; Exit
}

# ==========================================
# [STEP 2: MODIFY INPUT LIST]
# ==========================================
Write-Host "`n--- STEP 2: Updating Language List ---" -ForegroundColor Cyan

# TSF Format: LangID:CLSID{ProfileGUID}
# For Weasel, ProfileGUID is same as CLSID
$RimeTip     = "0404:$WeaselGuid$WeaselGuid"
$BopomofoTip = "0404:$MsBopomofoGuid"

try {
    $CurrentList = Get-WinUserLanguageList
    
    # 1. Get/Create zh-TW
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    if (-not $TwLang) {
        Write-Host "Creating zh-TW..."
        $TwLang = (New-WinUserLanguageList "zh-TW")[0]
        $CurrentList.Add($TwLang)
    }

    # 2. Add Rime
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "Adding Rime ($RimeTip)..."
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "Rime is already in the list object."
    }

    # 3. Remove Bopomofo (Conditional)
    if ($TwLang.InputMethodTips -contains $BopomofoTip) {
        Write-Host "Removing Microsoft Bopomofo..."
        $TwLang.InputMethodTips.Remove($BopomofoTip)
    }

    # 4. Apply
    Write-Host "Applying settings to Windows..."
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    
    # 5. Verification
    Start-Sleep -Seconds 2
    $VerifyList = Get-WinUserLanguageList
    $VerifyTw = $VerifyList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($VerifyTw.InputMethodTips -contains $RimeTip) {
        Write-Host "VERIFIED: Rime is active!" -ForegroundColor Green
        
        # Lock UI (Optional)
        Set-WinUILanguageOverride -Language "zh-TW"
        Write-Host "UI Locked to zh-TW."
    } else {
        Write-Host "WARNING: Windows dropped Rime from the list." -ForegroundColor Red
    }

} catch {
    Write-Error "Error: $_"
}

# Cleanup
if (Test-Path "$env:TEMP\addrime_elevated.ps1") { Remove-Item "$env:TEMP\addrime_elevated.ps1" -ErrorAction SilentlyContinue }

Write-Host "`nDone."
Read-Host "Press Enter to exit..."
#V5

