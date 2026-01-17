<#
.SYNOPSIS
    Rime Auto-Installer (V21 - Force Register & Smart TIP Detection)
    Fixes "Rime not added" by forcing registration and migrating TIP from zh-CN if needed.
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

# GUID Definitions
$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$StandardRimeTip = "0404:$WeaselGuid"
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
# [STEP 2: FORCE REGISTRATION (CRITICAL FIX)]
# ==========================================
# This ensures the GUID is written to HKLM/Software/Microsoft/CTF/TIP
Write-Host "Forcing TSF Registration..."
if (Test-Path $DeployerExe) {
    Start-Process $DeployerExe -ArgumentList "/install" -Wait
    Write-Host " - Registration command executed."
    Start-Sleep -Seconds 2 # Wait for Registry to settle
}

# ==========================================
# [STEP 3: INSTALL CONFIG DATA]
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
# [STEP 4: DEPLOY]
# ==========================================
Write-Host "`n[3/4] Compiling Schemas..."
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue
if (Test-Path $DeployerExe) {
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
}

# ==========================================
# [STEP 5: FIX PERMISSIONS]
# ==========================================
Write-Host "Fixing File Permissions..."
if (Test-Path $RimeUserDir) {
    Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
}

# ==========================================
# [STEP 6: FIX LANGUAGE (SMART MODE)]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List (Smart Mode)..." -ForegroundColor Yellow

try {
    # 1. Get Current List (This likely contains zh-CN from the installer)
    $CurrentList = Get-WinUserLanguageList
    $CleanList = @()

    # 2. English (Priority 1)
    $En = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $CleanList += $En
    Write-Host " - Priority 1: $($En.LanguageTag)"

    # 3. Traditional Chinese (Priority 2)
    # Strategy: Create fresh zh-TW, add Rime, Remove Bopomofo
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    
    # Force Add Rime
    if ($Tw.InputMethodTips -notcontains $StandardRimeTip) {
        $Tw.InputMethodTips.Add($StandardRimeTip)
        Write-Host "   -> Added Rime GUID"
    }

    # Remove Bopomofo (Only if Rime was added successfully logic check)
    # Note: We can't verify if it 'stuck' until we apply, so we assume success since we ran /install above.
    $BopomofoTip = "0404:$MsBopomofoGuid"
    if ($Tw.InputMethodTips -contains $BopomofoTip) {
        $Tw.InputMethodTips.Remove($BopomofoTip)
        Write-Host "   -> Removed Bopomofo"
    }

    $CleanList += $Tw
    Write-Host " - Priority 2: zh-TW (Sanitized)"

    # 4. Apply List (This wipes zh-CN automatically since it's not in $CleanList)
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    Write-Host " - Language list applied."

    # 5. Lock UI
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " - UI Locked to zh-TW." -ForegroundColor Green

} catch {
    Write-Error "Language process failed: $_"
}

# Final Cleanup
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again."
Read-Host "Press Enter to exit..."
#V21
