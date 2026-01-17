<#
.SYNOPSIS
    Rime Auto-Installer (V16 - Remove MS Bopomofo)
    Winget Install + Permission Fix + UI Fix + REMOVE Microsoft Bopomofo.
2601180237
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

# ==========================================
# [STEP 1: INSTALL VIA WINGET]
# ==========================================
Write-Host "Checking for Weasel Version $TargetVersion..." -ForegroundColor Cyan

if (-not (Test-Path $TargetDir)) {
    Write-Host "Target folder missing. Initiating Winget installation..."
    
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget not found. Please install manually."
        Read-Host "Press Enter to exit..."; Exit
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

# System Data
$TempProgZip = "$env:TEMP\rime_prog_data.zip"
try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    if (!(Test-Path $RimeDataDir)) { New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null }
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
} catch { Write-Warning "SysData Fail: $_" }

# User Data
$TempUserZip = "$env:TEMP\rime_user_data.zip"
try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
} catch { Write-Warning "UserData Fail: $_" }

# Clean Temp
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
# [STEP 4: FIX PERMISSIONS (icacls)]
# ==========================================
Write-Host "Fixing File Permissions (icacls)..."
if (Test-Path $RimeUserDir) {
    # Force full control for Users to avoid "Manual Redeploy" issue
    Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
}

# ==========================================
# [STEP 5: FIX LANGUAGE & REMOVE BOPOMOFO]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List..." -ForegroundColor Yellow

try {
    $CleanList = @()
    $CurrentList = Get-WinUserLanguageList

    # 5.1 ENGLISH (Priority 1)
    $EnglishLang = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $EnglishLang) { $EnglishLang = (New-WinUserLanguageList "en-US")[0] }
    $CleanList += $EnglishLang
    Write-Host " - Priority 1: $($EnglishLang.LanguageTag)"

    # 5.2 TRADITIONAL CHINESE (Priority 2 - Rime ONLY)
    $TwLang = (New-WinUserLanguageList "zh-TW")[0]
    $RimeTip = "0404:$WeaselGuid"
    
    # *** CRITICAL FIX: CLEAR DEFAULT INPUT METHODS (Removes MS Bopomofo) ***
    $TwLang.InputMethodTips.Clear()
    
    # Add ONLY Rime
    $TwLang.InputMethodTips.Add($RimeTip)
    
    $CleanList += $TwLang
    Write-Host " - Priority 2: zh-TW (Rime Only - MS Bopomofo Removed)"

    # 5.3 APPLY LIST
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    Write-Host " - Language list cleaned."

    # 5.4 FORCE UI TO TRADITIONAL CHINESE
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " - Display Language LOCKED to: zh-TW" -ForegroundColor Green

} catch {
    Write-Error "Language fix failed: $_"
}

# Final Cleanup
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Microsoft Bopomofo has been removed."
Write-Host "Please Sign Out and Sign In again to see the UI changes."
Read-Host "Press Enter to exit..."

