<#
.SYNOPSIS
    Rime Auto-Installer (V7 - Permission Fix & Process Cleanup)
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
$TargetDir     = "C:\Program Files\Rime\weasel-$TargetVersion"
$DeployerExe   = "$TargetDir\WeaselDeployer.exe" 
# Data path inside version folder
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

if (-not (Test-Path $TargetDir)) {
    Write-Host "Target folder missing. Invoking Winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget not found."; Read-Host "Press Enter to exit..."; Exit
    }

    try {
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Installation failed: $_"; Read-Host "Press Enter to exit..."; Exit
    }

    Write-Host "Waiting for installer..." -NoNewline
    $Retries = 0; $MaxRetries = 30
    do { Start-Sleep -Seconds 1; Write-Host "." -NoNewline; $Retries++; $Exists = Test-Path $DeployerExe } until ($Exists -or ($Retries -ge $MaxRetries))
    Write-Host "" 

    if (-not (Test-Path $DeployerExe)) { throw "Timed out waiting for '$DeployerExe'." }
    Write-Host "Weasel verified." -ForegroundColor Green
} else {
    Write-Host "Weasel $TargetVersion found." -ForegroundColor Green
}

# ==========================================
# [STEP 2: INSTALL SYSTEM DATA]
# ==========================================
Write-Host "`n[2/4] Installing System Data..."
$TempProgZip = "$env:TEMP\rime_prog_data.zip"
try {
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProgZip
    if (!(Test-Path $RimeDataDir)) { New-Item -ItemType Directory -Path $RimeDataDir -Force | Out-Null }
    Expand-Archive -Path $TempProgZip -DestinationPath $RimeDataDir -Force
    Write-Host "System Data installed to: $RimeDataDir"
} catch {
    Write-Error "SysData Fail: $_"; Read-Host "Exit..."; Exit
}

# ==========================================
# [STEP 3: INSTALL USER DATA]
# ==========================================
Write-Host "`n[3/4] Installing User Data..."
$TempUserZip = "$env:TEMP\rime_user_data.zip"
try {
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUserZip
    Expand-Archive -Path $TempUserZip -DestinationPath $RimeUserDir -Force
    Write-Host "User Data installed."
} catch {
    Write-Error "UserData Fail: $_"
}

# ==========================================
# [STEP 4: FIX PERMISSIONS & DEPLOY]
# ==========================================
Write-Host "`n[4/4] Finalizing..."

# 4.1 Permission Fix (Prevent Admin ownership lock-out)
Write-Host "Fixing User Data permissions..."
try {
    # Grant 'Users' group Full Control to the AppData\Rime folder
    $Acl = Get-Acl $RimeUserDir
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl $RimeUserDir $Acl
} catch {
    Write-Warning "Could not explicitly set permissions. Usually this is fine."
}

# 4.2 Cleanup Temp
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# 4.3 Kill Processes BEFORE Deploy
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

# 4.4 Execute Deploy (Admin Mode - compiles schemas)
if (Test-Path $DeployerExe) {
    Write-Host "Compiling schemas (Deploy)..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    
    # --- CRITICAL FIX ---
    # 4.5 KILL THE ADMIN SERVER
    # The deployer likely started WeaselServer as Admin. We MUST kill it.
    # This allows the User's desktop to start a fresh User-Level process automatically.
    Write-Host "Resetting Server process..."
    Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force
    
    Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
    Write-Host "You can switch to Rime input method immediately."
} else {
    Write-Error "Deployer missing."
}

Read-Host "Press Enter to exit..."
