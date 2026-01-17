<#
.SYNOPSIS
    Rime Auto-Installer (V18 - 3-Stage Sequential Language Fix)
    Stage 1: Initialize zh-TW
    Stage 2: Inject Rime
    Stage 3: Remove Bopomofo
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

$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
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
    Write-Host "Waiting for installer..." -NoNewline
    $Retries = 0; $MaxRetries = 30
    do { Start-Sleep -Seconds 1; Write-Host "." -NoNewline; $Retries++; $Exists = Test-Path $DeployerExe } until ($Exists -or ($Retries -ge $MaxRetries))
    Write-Host "" 
    if (-not (Test-Path $DeployerExe)) { throw "Timed out waiting for '$DeployerExe'." }
    Write-Host "Weasel installed." -ForegroundColor Green
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
# [STEP 5: FIX LANGUAGE (3-STAGE ROCKET)]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List (3-Stage Process)..." -ForegroundColor Yellow

$RimeTip = "0404:$WeaselGuid"
$BopomofoTip = "0404:$MsBopomofoGuid"

try {
    # --- STAGE A: BASE INITIALIZATION ---
    # Goal: Ensure System has [English, zh-TW(Default)]
    Write-Host "Stage A: Initializing Base Languages..."
    
    $List_A = @()
    # 1. English
    $Curr = Get-WinUserLanguageList
    $En = $Curr | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $List_A += $En
    
    # 2. zh-TW (Default Microsoft Bopomofo)
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    $List_A += $Tw
    
    Set-WinUserLanguageList $List_A -Force -ErrorAction Stop
    Write-Host " -> Base initialized."

    # --- STAGE B: INJECT RIME ---
    # Goal: Add Rime to the existing zh-TW
    Write-Host "Stage B: Injecting Rime..."
    
    # Reload fresh list from system
    $List_B = Get-WinUserLanguageList
    $Tw_Target = $List_B | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($Tw_Target) {
        if ($Tw_Target.InputMethodTips -notcontains $RimeTip) {
            $Tw_Target.InputMethodTips.Add($RimeTip)
            Set-WinUserLanguageList $List_B -Force -ErrorAction Stop
            Write-Host " -> Rime injected successfully."
        } else {
            Write-Host " -> Rime already present."
        }
    } else {
        throw "Critical: zh-TW missing after Stage A."
    }

    # --- STAGE C: REMOVE BOPOMOFO & LOCK UI ---
    # Goal: Remove MS Bopomofo and Lock UI
    Write-Host "Stage C: Removing Bopomofo & Locking UI..."
    
    # Reload fresh list again
    $List_C = Get-WinUserLanguageList
    $Tw_Final = $List_C | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($Tw_Final) {
        if ($Tw_Final.InputMethodTips -contains $BopomofoTip) {
            # Only remove if Rime is actually there (Safety)
            if ($Tw_Final.InputMethodTips -contains $RimeTip) {
                $Tw_Final.InputMethodTips.Remove($BopomofoTip)
                Set-WinUserLanguageList $List_C -Force -ErrorAction Stop
                Write-Host " -> Microsoft Bopomofo removed."
            } else {
                Write-Warning " -> Rime not detected. Skipping Bopomofo removal to prevent empty list."
            }
        }
    }

    # Lock UI Language
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " -> UI Locked to zh-TW." -ForegroundColor Green

} catch {
    Write-Error "Language process failed: $_"
}

# Final Cleanup
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again to fully apply settings."
Read-Host "Press Enter to exit..."
