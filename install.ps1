<#
.SYNOPSIS
    Automated Rime (Weasel) Customization Installer
    
.DESCRIPTION
    This script downloads custom configuration files from a remote repository
    and deploys them to both the Program Files directory and the User AppData directory.
    It automatically requests Administrator privileges if not already running as Admin.

.NOTES
    Target Structure for data.zip:
        root/
          ├── liur_abc.yaml
          └── opencc/
                └── liur_config.json
#>

# ==========================================
# [CONFIGURATION AREA] - PLEASE EDIT THIS
# ==========================================

# 1. The RAW URL of this script itself (Required for auto-elevation)
$ScriptUrl = "https://raw.githubusercontent.com/perrier8wu/rime-win11-deploy/main/install.ps1"

# 2. The RAW URL of the System Data ZIP (Contents for 'Program Files (x86)\Rime\data')
$ProgDataUrl = "https://raw.githubusercontent.com/perrier8wu/rime-win11-deploy/main/data.zip"

# 3. The RAW URL of the User Data ZIP (Contents for '%APPDATA%\Rime')
$UserDataUrl = "https://raw.githubusercontent.com/perrier8wu/rime-win11-deploy/main/rime_user_data.zip"

# ==========================================
# [AUTO-ELEVATION LOGIC]
# ==========================================

$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Requesting Administrator privileges to write to Program Files..." -ForegroundColor Yellow
    
    # Download the script to a temporary file to execute it with elevated privileges
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    
    try {
        Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript
    }
    catch {
        Write-Error "Failed to download self for elevation. Please check '$ScriptUrl'."
        Start-Sleep -Seconds 5
        Exit
    }

    # Start a new PowerShell process as Administrator
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    
    # Exit the current non-admin process
    Exit
}

# ==========================================
# [MAIN INSTALLATION LOGIC]
# ==========================================

$ErrorActionPreference = "Stop"
Write-Host "Administrator privileges confirmed. Starting installation..." -ForegroundColor Green

# Define Paths
$RimeProgDir = "C:\Program Files (x86)\Rime"
$RimeDataDir = "$RimeProgDir\data"
$RimeUserDir = "$env:APPDATA\Rime"

# Check if Rime is installed
if (-not (Test-Path $RimeProgDir)) {
    Write-Error "Error: Rime installation directory not found at '$RimeProgDir'."
    Write-Host "Please install Weasel (Rime) first."
    Read-Host "Press Enter to exit..."
    Exit
}

# ---------------------------------------------------
# Step 1: Install System Data (Program Files)
# ---------------------------------------------------
Write-Host "`n[1/4] Downloading and installing System Data..."
Write-Host "Target: $RimeDataDir"

$TempProgZip = "$env:TEMP\rime_prog_data.zip"

try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    
    # Extract to 'data' folder. 
    # Since data.zip structure matches the 'data' folder content, this merges perfectly.
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    
    Write-Host "System Data installed successfully." -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to download or extract System Data. Details: $_"
    Read-Host "Press Enter to exit..."
    Exit
}

# ---------------------------------------------------
# Step 2: Install User Data (AppData)
# ---------------------------------------------------
Write-Host "`n[2/4] Downloading and installing User Data..."
Write-Host "Target: $RimeUserDir"

$TempUserZip = "$env:TEMP\rime_user_data.zip"

try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    
    # Force overwrite user data
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    
    Write-Host "User Data installed successfully." -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to download or extract User Data. Details: $_"
}

# ---------------------------------------------------
# Step 3: Cleanup Temporary Files
# ---------------------------------------------------
Write-Host "`n[3/4] Cleaning up temporary files..."
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# ---------------------------------------------------
# Step 4: Redeploy Rime
# ---------------------------------------------------
Write-Host "`n[4/4] Redeploying Rime..."

# Kill Weasel processes to release file locks
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

$DeployerExe = "$RimeProgDir\weasel-deployer.exe"

if (Test-Path $DeployerExe) {
    Write-Host "Executing deployment tool..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
}
else {
    Write-Warning "Deployer tool not found. Please manually select 'Redeploy' from the taskbar tray."
}

Write-Host "`nInstallation finished."
Read-Host "Press Enter to exit..."