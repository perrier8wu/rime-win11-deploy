<#
.SYNOPSIS
    addRime.ps1 (Final Fix) - Activate the REAL Weasel (¤p¯T²@)
    1. Fixes Registry Name by running official tool properly.
    2. Adds "¤p¯T²@" to zh-TW.
    3. Removes Microsoft Bopomofo.
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
$WeaselVersion  = "0.17.4"
$WeaselDir      = "C:\Program Files\Rime\weasel-$WeaselVersion"
$WeaselExe      = "$WeaselDir\WeaselDeployer.exe"
# The OFFICIAL GUID for Weasel (¤p¯T²@)
$WeaselClsid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$BopomofoGuid   = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: REPAIR REGISTRY (THE NAME FIX)]
# ==========================================
Write-Host "--- STEP 1: Running Official Registration (Fixing Name) ---" -ForegroundColor Cyan

if (Test-Path $WeaselExe) {
    Write-Host "Executing WeaselDeployer to restore '¤p¯T²@' name..."
    # IMPORTANT: We MUST set WorkingDirectory, otherwise it crashes silently!
    $Proc = Start-Process -FilePath $WeaselExe -ArgumentList "/install" -WorkingDirectory $WeaselDir -PassThru -Wait
    
    if ($Proc.ExitCode -eq 0) {
        Write-Host "[SUCCESS] Official registration complete." -ForegroundColor Green
    } else {
        Write-Warning "Registration exited with code $($Proc.ExitCode). Assuming it worked."
    }
    # Wait for Registry I/O
    Start-Sleep -Seconds 2
} else {
    Write-Error "CRITICAL: WeaselDeployer not found at $WeaselExe"
    Pause; Exit
}

# ==========================================
# [STEP 2: ADD "¤p¯T²@" & REMOVE BOPOMOFO]
# ==========================================
Write-Host "`n--- STEP 2: Configuring Input Methods ---" -ForegroundColor Cyan

try {
    # This GUID now points to "¤p¯T²@" (because we ran /install above)
    $RealWeaselTip = "0404:$WeaselClsid$WeaselClsid"
    $BopomofoTip   = "0404:$BopomofoGuid"
    
    $CurrentList = Get-WinUserLanguageList
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if (-not $TwLang) {
        Write-Host "Creating zh-TW..."
        $TwLang = (New-WinUserLanguageList "zh-TW")[0]
        $CurrentList.Add($TwLang)
    }

    # 1. Add Official Weasel
    if ($TwLang.InputMethodTips -notcontains $RealWeaselTip) {
        Write-Host "Adding '¤p¯T²@' to list..."
        $TwLang.InputMethodTips.Add($RealWeaselTip)
    } else {
        Write-Host "'¤p¯T²@' is already in the list."
    }

    # 2. Remove Bopomofo
    if ($TwLang.InputMethodTips -contains $BopomofoTip) {
        Write-Host "Removing Microsoft Bopomofo..."
        $TwLang.InputMethodTips.Remove($BopomofoTip)
    }

    # 3. Apply
    Write-Host "Applying settings..."
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    
    # 4. Lock UI (Optional, consistent with your needs)
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host "UI Locked to Traditional Chinese."

    Write-Host "[SUCCESS] Configuration updated." -ForegroundColor Green
    Write-Host "Please check your language bar. It should now show '¤p¯T²@'."

} catch {
    Write-Error "Error: $_"
}

# Cleanup
if (Test-Path "$env:TEMP\addrime_elevated.ps1") { Remove-Item "$env:TEMP\addrime_elevated.ps1" -ErrorAction SilentlyContinue }

Write-Host "`nDone."
Read-Host "Press Enter to exit..."
#V4

