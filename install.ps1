<#
.SYNOPSIS
    Rime Auto-Installer (Clean Final)
    Integrates Winget Install, Registry Sync, Permission Fix, and Language Setup.
#>

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_final_install.ps1"
    $MyInvocation.MyCommand.ScriptBlock | Out-File $TempScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [CONFIGURATION]
# ==========================================
$TargetVersion = "0.17.4"
$WeaselDir     = "C:\Program Files\Rime\weasel-$TargetVersion"
$DeployerExe   = "$WeaselDir\WeaselDeployer.exe" 
$RimeUserDir   = "$env:APPDATA\Rime"

# URLs (Data Config)
$ProgDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# GUIDs
$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$BopomofoGuid  = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: INSTALL VIA WINGET]
# ==========================================
Write-Host "--- [1/5] Installing Weasel via Winget ---" -ForegroundColor Cyan

if (-not (Test-Path $DeployerExe)) {
    try {
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Winget failed: $_"; Pause; Exit
    }
    
    # Wait for file system
    Write-Host "Waiting for files..." -NoNewline
    for ($i=0; $i -lt 30; $i++) { 
        if (Test-Path $DeployerExe) { break }
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
    }
    Write-Host ""
} else {
    Write-Host "Weasel already installed." -ForegroundColor Green
}

if (-not (Test-Path $DeployerExe)) { Write-Error "Installation failed: Files not found."; Pause; Exit }

# ==========================================
# [STEP 2: SYNC REGISTRY (HKLM -> HKCU)]
# ==========================================
# This is the "Magic Fix" to make Windows see '¤p¯T²@' immediately
Write-Host "`n--- [2/5] Syncing Registry (HKLM -> HKCU) ---" -ForegroundColor Cyan

$HklmTip  = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselGuid"
$HklmProf = "$HklmTip\LanguageProfile\0x00000404\$WeaselGuid"
$HkcuTip  = "HKCU:\SOFTWARE\Microsoft\CTF\TIP\$WeaselGuid"
$HkcuProf = "$HkcuTip\LanguageProfile\0x00000404\$WeaselGuid"

if (Test-Path $HklmProf) {
    # Ensure User Keys Exist
    if (-not (Test-Path $HkcuTip))  { New-Item -Path $HkcuTip -Force | Out-Null }
    if (-not (Test-Path $HkcuProf)) { New-Item -Path $HkcuProf -Force | Out-Null }

    # Sync Properties (Description, Icon, Enable)
    try {
        Get-ItemProperty -Path $HklmTip | ForEach-Object {
            if ($_.Description) { Set-ItemProperty -Path $HkcuTip -Name "Description" -Value $_.Description -Force }
            if ($_.Icon)        { Set-ItemProperty -Path $HkcuTip -Name "Icon" -Value $_.Icon -Force }
            Set-ItemProperty -Path $HkcuTip -Name "Enable" -Value 1 -Type DWord -Force
        }
        Get-ItemProperty -Path $HklmProf | ForEach-Object {
            if ($_.Description) { Set-ItemProperty -Path $HkcuProf -Name "Description" -Value $_.Description -Force }
            if ($_.Icon)        { Set-ItemProperty -Path $HkcuProf -Name "Icon" -Value $_.Icon -Force }
            Set-ItemProperty -Path $HkcuProf -Name "Enable" -Value 1 -Type DWord -Force
        }
        Write-Host "Registry Synced Successfully." -ForegroundColor Green
    } catch { Write-Warning "Registry Sync Warning: $_" }
} else {
    Write-Warning "HKLM Registry missing. Installation might be incomplete."
}

# ==========================================
# [STEP 3: CONFIG DATA & DEPLOY]
# ==========================================
Write-Host "`n--- [3/5] Installing Config & Deploying ---" -ForegroundColor Cyan

# Download & Unzip Data
$TempProg = "$env:TEMP\rime_prog.zip"
$TempUser = "$env:TEMP\rime_user.zip"
Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProg
Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUser

Expand-Archive $TempProg -DestinationPath "$WeaselDir\data" -Force
Expand-Archive $TempUser -DestinationPath $RimeUserDir -Force

# Deploy (Generate bin files)
Start-Process $DeployerExe -ArgumentList "/deploy" -Wait

# FIX PERMISSIONS (icacls) - Critical for "Manual Redeploy" issue
Write-Host "Fixing User Permissions..."
if (Test-Path $RimeUserDir) {
    Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
}

# Clean Temp
Remove-Item $TempProg, $TempUser -ErrorAction SilentlyContinue

# ==========================================
# [STEP 4: SETUP INPUT METHODS]
# ==========================================
Write-Host "`n--- [4/5] Setting Input Methods ---" -ForegroundColor Cyan

try {
    $TargetTip   = "0404:$WeaselGuid$WeaselGuid"
    $BopomofoTip = "0404:$BopomofoGuid"
    
    $CurrentList = Get-WinUserLanguageList
    $CleanList   = @()

    # 1. English (Priority 1)
    $En = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $CleanList += $En
    Write-Host " - Added: English ($($En.LanguageTag))"

    # 2. Traditional Chinese (Priority 2)
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    
    # Add Weasel
    if ($Tw.InputMethodTips -notcontains $TargetTip) {
        $Tw.InputMethodTips.Add($TargetTip)
        Write-Host " - Added: ¤p¯T²@ (Weasel)"
    }
    
    # Remove Bopomofo (Only if Weasel is present)
    if ($Tw.InputMethodTips -contains $BopomofoTip) {
        $Tw.InputMethodTips.Remove($BopomofoTip)
        Write-Host " - Removed: Microsoft Bopomofo"
    }
    
    $CleanList += $Tw

    # Apply List
    Set-WinUserLanguageList $CleanList -Force -ErrorAction Stop
    Write-Host "Language list updated." -ForegroundColor Green

} catch {
    Write-Error "Language Setup Failed: $_"
}

# ==========================================
# [STEP 5: LOCK UI & CLEANUP]
# ==========================================
Write-Host "`n--- [5/5] Finalizing ---" -ForegroundColor Cyan

# Force UI to Traditional Chinese
Set-WinUILanguageOverride -Language "zh-TW"
Write-Host "UI Locked to zh-TW."

# Kill Processes to ensure clean restart
Stop-Process -Name "WeaselServer", "WeaselDeployer" -ErrorAction SilentlyContinue -Force

Write-Host "`n[SUCCESS] Installation Complete!" -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again to fully apply the UI language."
Read-Host "Press Enter to exit..."
#V23

