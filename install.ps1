<#
.SYNOPSIS
    Automated Rime (Weasel) Customization Installer (x64/x86 Compatible)
#>

# ==========================================
# [CONFIGURATION AREA] - PLEASE EDIT THIS
# ==========================================

# 1. The RAW URL of this script itself
$ScriptUrl = "https://perrier8wu.github.io/rime-win11-deploy/install.ps1"

# 2. The RAW URL of the System Data ZIP
$ProgDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"

# 3. The RAW URL of the User Data ZIP
$UserDataUrl = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [AUTO-ELEVATION LOGIC]
# ==========================================

$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_installer_elevated.ps1"
    try {
        Invoke-RestMethod -Uri $ScriptUrl -OutFile $TempScript
    }
    catch {
        Write-Error "Failed to download self. Check URL: $ScriptUrl"
        Start-Sleep -Seconds 5; Exit
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [PATH DETECTION LOGIC] - NEW!
# ==========================================
Write-Host "Admin privileges confirmed. Detecting Rime installation..." -ForegroundColor Green

$CandidatePaths = @(
    "$env:ProgramFiles\Rime",       # C:\Program Files\Rime (x64 default)
    "${env:ProgramFiles(x86)}\Rime" # C:\Program Files (x86)\Rime (Old/x86 default)
)

$RimeProgDir = $null

foreach ($path in $CandidatePaths) {
    if (Test-Path $path) {
        # 1. Check root
        if (Test-Path "$path\weasel-deployer.exe") {
            $RimeProgDir = $path
            break
        }
        # 2. Check subfolders (e.g., weasel-0.17.4)
        $Versioned = Get-ChildItem -Path $path -Directory -Filter "weasel-*" -ErrorAction SilentlyContinue
        foreach ($vFolder in $Versioned) {
            if (Test-Path "$($vFolder.FullName)\weasel-deployer.exe") {
                $RimeProgDir = $vFolder.FullName
                break
            }
        }
    }
    if ($RimeProgDir) { break }
}

if (-not $RimeProgDir) {
    Write-Error "Error: Could not find Rime installation (weasel-deployer.exe)."
    Write-Host "Checked paths:"
    $CandidatePaths | ForEach-Object { Write-Host " - $_" }
    Read-Host "Press Enter to exit..."; Exit
}

$RimeDataDir = "$RimeProgDir\data"
$RimeUserDir = "$env:APPDATA\Rime"

Write-Host "Found Rime at: $RimeProgDir" -ForegroundColor Cyan
Write-Host "Data Directory: $RimeDataDir" -ForegroundColor Cyan

# ==========================================
# [MAIN INSTALLATION LOGIC]
# ==========================================
$ErrorActionPreference = "Stop"

# 1. System Data
Write-Host "`n[1/3] Installing System Data..."
$TempProgZip = "$env:TEMP\rime_prog_data.zip"
try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    Write-Host "Done."
} catch {
    Write-Error "Failed to install System Data. Details: $_"
    Read-Host "Press Enter to exit..."; Exit
}

# 2. User Data
Write-Host "`n[2/3] Installing User Data..."
$TempUserZip = "$env:TEMP\rime_user_data.zip"
try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    Write-Host "Done."
} catch {
    Write-Error "Failed to install User Data. Details: $_"
}

# 3. Cleanup & Deploy
Write-Host "`n[3/3] Cleaning up and Redeploying..."
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

$DeployerExe = "$RimeProgDir\weasel-deployer.exe"
Start-Process $DeployerExe -ArgumentList "/deploy" -Wait

Write-Host "`nInstallation Success! Enjoy Boshiamy." -ForegroundColor Green
Read-Host "Press Enter to exit..."
