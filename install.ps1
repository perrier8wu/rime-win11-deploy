<#
.SYNOPSIS
    Rime Auto-Installer (V22 - "Steal & Transplant" Strategy)
    DETECTS where the installer put Rime, CAPTURES the valid GUID, and TRANSPLANTS it to zh-TW.
#>

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    try { Invoke-RestMethod -Uri "https://perrier8wu.github.io/rime-win11-deploy/install.ps1" -OutFile $TempScript }
    catch { Write-Error "Download failed."; Start-Sleep 5; Exit }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [CONFIGURATION]
# ==========================================
$ProgDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"
$TargetVersion = "0.17.4"
$TargetDir     = "C:\Program Files\Rime\weasel-$TargetVersion"
$DeployerExe   = "$TargetDir\WeaselDeployer.exe" 
$RimeDataDir   = "$TargetDir\data" 
$RimeUserDir   = "$env:APPDATA\Rime"

# Weasel GUID fragment to search for
$WeaselGuidSig = "A3F61664" 
# Fallback GUID (Standard) just in case detection fails
$FallbackTip   = "0404:{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$MsBopomofoGuid = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: INSTALL VIA WINGET]
# ==========================================
Write-Host "Checking for Weasel Version $TargetVersion..." -ForegroundColor Cyan

if (-not (Test-Path $TargetDir)) {
    Write-Host "Target folder missing. Initiating Winget installation..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget not found."; Read-Host "Exit..."; Exit
    }
    try {
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Winget failed: $_"; Read-Host "Exit..."; Exit
    }

    # Wait for file system
    Write-Host "Waiting for installer..." -NoNewline
    $Retries = 0; $MaxRetries = 30
    do { Start-Sleep -Seconds 1; Write-Host "." -NoNewline; $Retries++; $Exists = Test-Path $DeployerExe } until ($Exists -or ($Retries -ge $MaxRetries))
    Write-Host "" 
    if (-not (Test-Path $DeployerExe)) { throw "Timed out waiting for '$DeployerExe'." }
    Write-Host "Weasel installed." -ForegroundColor Green
    
    # *** CRITICAL: Wait for Installer to register languages ***
    Write-Host "Waiting 5s for installer to touch Language List..."
    Start-Sleep -Seconds 5
} else {
    Write-Host "Already installed." -ForegroundColor Green
}

# ==========================================
# [STEP 2: INSTALL CONFIG DATA]
# ==========================================
Write-Host "`n[2/4] Installing Configuration Data..."
$TempProgZip = "$env:TEMP\rime_prog_data.zip"
try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    if (!(Test-Path $RimeDataDir)) { New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null }
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
} catch { Write-Warning "SysData Fail: $_" }

$TempUserZip = "$env:TEMP\rime_user_data.zip"
try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
} catch { Write-Warning "UserData Fail: $_" }

Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# ==========================================
# [STEP 3: DEPLOY]
# ==========================================
Write-Host "`n[3/4] Compiling Schemas..."
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue
if (Test-Path $DeployerExe) {
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
}

# ==========================================
# [STEP 4: FIX PERMISSIONS]
# ==========================================
Write-Host "Fixing File Permissions..."
if (Test-Path $RimeUserDir) {
    Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
}

# ==========================================
# [STEP 5: DETECT & TRANSPLANT RIME (THE FIX)]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List (Transplant Strategy)..." -ForegroundColor Yellow

try {
    # 1. SCAN for Rime in ANY language
    Write-Host "Scanning system for valid Rime registration..."
    $CurrentList = Get-WinUserLanguageList
    $DetectedTip = $null
    
    foreach ($Lang in $CurrentList) {
        foreach ($Tip in $Lang.InputMethodTips) {
            if ($Tip -match $WeaselGuidSig) {
                Write-Host " -> FOUND Rime in language: $($Lang.LanguageTag) | TIP: $Tip" -ForegroundColor Cyan
                $DetectedTip = $Tip
                break
            }
        }
        if ($DetectedTip) { break }
    }

    # 2. CONSTRUCT the Target TIP for zh-TW (0404)
    $TargetRimeTip = $null
    
    if ($DetectedTip) {
        # Format is usually LangID:ProfileGUID
        # We need to ensure it starts with 0404 (Traditional Chinese)
        $Split = $DetectedTip -split ":"
        if ($Split.Count -eq 2) {
            $TargetRimeTip = "0404:" + $Split[1]
            Write-Host " -> Constructed Transplant TIP: $TargetRimeTip"
        }
    }
    
    if (-not $TargetRimeTip) {
        Write-Warning " -> Could not detect Rime automatically. Using Standard Fallback."
        $TargetRimeTip = $FallbackTip
    }

    # 3. BUILD THE NEW CLEAN LIST
    $CleanList = @()

    # A. English (Priority 1)
    $En = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $CleanList += $En
    Write-Host " - Priority 1: $($En.LanguageTag)"

    # B. Traditional Chinese (Priority 2)
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    
    # C. INJECT RIME (The Transplant)
    if ($Tw.InputMethodTips -notcontains $TargetRimeTip) {
        $Tw.InputMethodTips.Add($TargetRimeTip)
        Write-Host "   -> Added Rime ($TargetRimeTip)"
    }

    # D. REMOVE BOPOMOFO (Only if Rime added)
    # Since we are building a NEW object, we don't need to check "if exists", we just don't add it.
    # BUT New-WinUserLanguageList adds it by default, so we MUST remove it.
    $BopomofoTip = "0404:$MsBopomofoGuid"
    if ($Tw.InputMethodTips -contains $BopomofoTip) {
        $Tw.InputMethodTips.Remove($BopomofoTip)
        Write-Host "   -> Removed Bopomofo"
    }
    
    # SAFETY: If list is empty, put Bopomofo back
    if ($Tw.InputMethodTips.Count -eq 0) {
        Write-Warning "   -> Rime add failed? Restoring Bopomofo."
        $Tw.InputMethodTips.Add($BopomofoTip)
    }

    $CleanList += $Tw
    Write-Host " - Priority 2: zh-TW (Rime Only)"

    # 4. APPLY (This wipes Simplified Chinese because we didn't add it to CleanList)
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    Write-Host " - Language list applied."

    # 5. LOCK UI
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " - UI Locked to zh-TW." -ForegroundColor Green

} catch {
    Write-Error "Language process failed: $_"
}

Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again."
Read-Host "Press Enter to exit..."
#V22

