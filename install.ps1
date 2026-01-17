<#
.SYNOPSIS
    Rime Auto-Installer & Customizer (Winget Edition - Version 0.17.4)
#>

# ==========================================
# [CONFIGURATION AREA]
# ==========================================
# URLs updated based on your repository
$ScriptUrl   = "https://perrier8wu.github.io/rime-win11-deploy/install.ps1"
$ProgDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [CONSTANTS]
# ==========================================
$TargetVersion = "0.17.4"
$RimeRoot      = "C:\Program Files\Rime"
$VersionDir    = "$RimeRoot\weasel-$TargetVersion"
$DeployerExe   = "$VersionDir\weasel-deployer.exe"
$RimeDataDir   = "$RimeRoot\data"
$RimeUserDir   = "$env:APPDATA\Rime"

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    try { 
        Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript 
    }
    catch { 
        Write-Error "Failed to download script. Check URL: $ScriptUrl"
        Start-Sleep 5; Exit 
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [STEP 1: CHECK & INSTALL RIME VIA WINGET]
# ==========================================
$ErrorActionPreference = "Stop"
Write-Host "Checking for Weasel Version $TargetVersion..." -ForegroundColor Cyan

if (-not (Test-Path $DeployerExe)) {
    Write-Warning "Weasel $TargetVersion not found. Initiating Winget installation..."
    
    # Check if Winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget is not installed on this system. Cannot install Rime automatically."
        Read-Host "Press Enter to exit..."; Exit
    }

    try {
        # Silent install specific version
        Write-Host "Downloading and installing Rime.Weasel $TargetVersion..."
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
        
        # Wait for file system to settle
        Start-Sleep -Seconds 5
        
        # Verify installation
        if (-not (Test-Path $DeployerExe)) {
            throw "Installation completed but target directory '$VersionDir' is missing."
        }
        Write-Host "Weasel installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "Winget installation failed. Details: $_"
        Write-Host "Please install Weasel 0.17.4 manually."
        Read-Host "Press Enter to exit..."; Exit
    }
} else {
    Write-Host "Weasel $TargetVersion is already installed." -ForegroundColor Green
}

# ==========================================
# [STEP 2: INSTALL SYSTEM DATA]
# ==========================================
Write-Host "`n[2/4] Installing System Data (Program Files)..."
Write-Host "Target: $RimeDataDir"

$TempProgZip = "$env:TEMP\rime_prog_data.zip"

try {
    # Download
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    
    # Ensure data directory exists
    if (!(Test-Path $RimeDataDir)) { New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null }
    
    # Unzip and Overwrite
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    Write-Host "System Data installed."
} catch {
    Write-Host "Error installing System Data: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit..."; Exit
}

# ==========================================
# [STEP 3: INSTALL USER DATA]
# ==========================================
Write-Host "`n[3/4] Installing User Data (AppData)..."
Write-Host "Target: $RimeUserDir"

$TempUserZip = "$env:TEMP\rime_user_data.zip"

try {
    # Download
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    
    # Unzip and Overwrite
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    Write-Host "User Data installed."
} catch {
    Write-Host "Error installing User Data: $_" -ForegroundColor Red
}

# ==========================================
# [STEP 4: CLEANUP & DEPLOY]
# ==========================================
Write-Host "`n[4/4] Finalizing..."

# Remove temp files
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# Stop processes to ensure clean reload
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

# Run Deployer
if (Test-Path $DeployerExe) {
    Write-Host "Executing Weasel Deployer..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    Write-Host "`nAll operations completed successfully! Enjoy Boshiamy." -ForegroundColor Green
} else {
    Write-Warning "Deployer executable not found."
}

Read-Host "Press Enter to exit..."
