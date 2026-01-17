<#
.SYNOPSIS
    Rime Auto-Installer (V6 - Correct Data Path inside Version Folder)
2601171846
#>

# ==========================================
# [CONFIGURATION AREA]
# ==========================================
$ScriptUrl   = "https://perrier8wu.github.io/rime-win11-deploy/install.ps1"
$ProgDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [CONSTANTS]
# ==========================================
$TargetVersion = "0.17.4"
# The folder where Winget installs files
$TargetDir     = "C:\Program Files\Rime\weasel-$TargetVersion"

# FIXED: Deployer filename (WeaselDeployer.exe)
$DeployerExe   = "$TargetDir\WeaselDeployer.exe" 

# FIXED: Data directory is now INSIDE the version folder
$RimeDataDir   = "$TargetDir\data" 

$RimeUserDir   = "$env:APPDATA\Rime"

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    try { Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript }
    catch { Write-Error "Download failed. Check URL: $ScriptUrl"; Start-Sleep 5; Exit }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [STEP 1: CHECK & INSTALL VIA WINGET]
# ==========================================
$ErrorActionPreference = "Stop"
Write-Host "Checking for Weasel Version $TargetVersion..." -ForegroundColor Cyan

# Check if the specific version folder exists
if (-not (Test-Path $TargetDir)) {
    Write-Host "Target folder '$TargetDir' missing. Invoking Winget..."
    
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget not found. Please install manually."
        Read-Host "Press Enter to exit..."; Exit
    }

    try {
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Installation failed: $_"; Read-Host "Press Enter to exit..."; Exit
    }

    # Wait loop for filesystem
    Write-Host "Waiting for installer to finish..." -NoNewline
    $Retries = 0
    $MaxRetries = 30
    do {
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
        $Retries++
        $Exists = Test-Path $DeployerExe
    } until ($Exists -or ($Retries -ge $MaxRetries))
    Write-Host "" 

    if (-not (Test-Path $DeployerExe)) {
        throw "Timed out waiting for '$DeployerExe'. Please check installation."
    }
    Write-Host "Weasel verified at: $DeployerExe" -ForegroundColor Green
} else {
    Write-Host "Weasel $TargetVersion is already installed." -ForegroundColor Green
}

# ==========================================
# [STEP 2: INSTALL SYSTEM DATA]
# ==========================================
Write-Host "`n[2/4] Installing System Data..."
Write-Host "Target: $RimeDataDir"
$TempProgZip = "$env:TEMP\rime_prog_data.zip"

try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    
    # Ensure the 'data' folder inside weasel-0.17.4 exists
    if (!(Test-Path $RimeDataDir)) { 
        New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null 
    }
    
    # Unzip into weasel-0.17.4\data
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    Write-Host "System Data installed."
} catch {
    Write-Host "Error installing System Data: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit..."; Exit
}

# ==========================================
# [STEP 3: INSTALL USER DATA]
# ==========================================
Write-Host "`n[3/4] Installing User Data..."
Write-Host "Target: $RimeUserDir"
$TempUserZip = "$env:TEMP\rime_user_data.zip"

try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    Write-Host "User Data installed."
} catch {
    Write-Host "Error installing User Data: $_" -ForegroundColor Red
}

# ==========================================
# [STEP 4: CLEANUP & DEPLOY]
# ==========================================
Write-Host "`n[4/4] Finalizing..."

Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

if (Test-Path $DeployerExe) {
    Write-Host "Executing Weasel Deployer..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    Write-Host "`nSuccess! Boshiamy installation complete." -ForegroundColor Green
} else {
    Write-Error "Deployer executable missing at the last step."
}

Read-Host "Press Enter to exit..."
