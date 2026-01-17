<#
.SYNOPSIS
    Rime Customization Installer (Strictly bound to Weasel 0.17.4)
#>

# ==========================================
# [CONFIGURATION AREA]
# ==========================================
# Please update these URLs to your actual GitHub raw links
$ScriptUrl   = "https://perrier8wu.github.io/rime-win11-deploy/install.ps1"
$ProgDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [STRICT VERSION CHECK]
# ==========================================
$TargetVersionDir = "C:\Program Files\Rime\weasel-0.17.4"

Write-Host "Checking for Weasel 0.17.4 installation..." -ForegroundColor Gray

if (-not (Test-Path $TargetVersionDir)) {
    Write-Host "`n[ERROR] Target version directory not found!" -ForegroundColor Red
    Write-Host "Expected: $TargetVersionDir" -ForegroundColor Red
    Write-Host "This installer is strictly bound to Weasel version 0.17.4."
    Write-Host "Installation aborted."
    Read-Host "Press Enter to exit..."
    Exit
}

Write-Host "Version 0.17.4 found. Proceeding..." -ForegroundColor Green

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
# Now that we know the folder exists, we request Admin rights to write into it.
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    try { 
        Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript 
    }
    catch { 
        Write-Error "Failed to download self for elevation. Please check URL."
        Start-Sleep 5; Exit 
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [INSTALLATION LOGIC]
# ==========================================
$ErrorActionPreference = "Stop"

# Define Paths based on the validated version structure
$DeployerExe = "$TargetVersionDir\weasel-deployer.exe"
$RimeDataDir = "C:\Program Files\Rime\data"  # Sibling directory to weasel-0.17.4
$RimeUserDir = "$env:APPDATA\Rime"

# 1. System Data (Program Files)
Write-Host "`n[1/3] Installing System Data..."
Write-Host "Target: $RimeDataDir"
$TempProgZip = "$env:TEMP\rime_prog_data.zip"

try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    
    # Ensure data directory exists (it should, but just in case)
    if (!(Test-Path $RimeDataDir)) { New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null }
    
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    Write-Host "System Data installed."
} catch {
    Write-Host "Error installing System Data: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit..."; Exit
}

# 2. User Data (AppData)
Write-Host "`n[2/3] Installing User Data..."
Write-Host "Target: $RimeUserDir"
$TempUserZip = "$env:TEMP\rime_user_data.zip"

try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    Write-Host "User Data installed."
} catch {
    Write-Host "Error installing User Data: $_" -ForegroundColor Red
}

# 3. Redeploy
Write-Host "`n[3/3] Redeploying Rime..."

# Cleanup temp files
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# Stop processes
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

if (Test-Path $DeployerExe) {
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    Write-Host "`nSuccess! Boshiamy installation complete." -ForegroundColor Green
} else {
    Write-Warning "Deployer not found at expected path: $DeployerExe"
}

Read-Host "Press Enter to exit..."
