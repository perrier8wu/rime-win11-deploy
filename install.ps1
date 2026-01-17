<#
.SYNOPSIS
    Rime Auto-Installer (V8 - Fix Simplified Chinese Issue)
2601180109
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
$RimeDataDir   = "$TargetDir\data" 
$RimeUserDir   = "$env:APPDATA\Rime"

# Weasel TSF GUID (Standard)
$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"

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
Write-Host "`n[4/4] Finalizing & Deploying..."

# Permission Fix
try {
    $Acl = Get-Acl $RimeUserDir
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl $RimeUserDir $Acl
} catch { Write-Warning "Perms fix skipped." }

# Cleanup Temp
Remove-Item $TempProgZip -ErrorAction SilentlyContinue
Remove-Item $TempUserZip -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\rime_installer_elevated.ps1" -ErrorAction SilentlyContinue

# Kill Processes
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue

# Execute Deploy
if (Test-Path $DeployerExe) {
    Write-Host "Compiling schemas..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
    Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force
}

# ==========================================
# [STEP 5: LANGUAGE CLEANUP (NEW!)]
# ==========================================
Write-Host "`n[5/5] Sanitizing Language List (Removing Simplified Chinese)..." -ForegroundColor Yellow

try {
    # 1. Get current list
    $OldList = Get-WinUserLanguageList
    $NewList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]
    
    # 2. Ensure zh-TW exists in our new plan
    $HasTW = $false
    
    # 3. Filter the list
    foreach ($Lang in $OldList) {
        # SKIP Simplified Chinese (zh-CN)
        if ($Lang.LanguageTag -eq "zh-CN") {
            Write-Host " - Removing Simplified Chinese (zh-CN)..." -ForegroundColor Red
            continue 
        }
        
        # Track if we have TW
        if ($Lang.LanguageTag -eq "zh-TW") { $HasTW = $true }
        
        $NewList.Add($Lang)
    }

    # 4. If TW is missing (rare, but possible), add it
    if (-not $HasTW) {
        Write-Host " - Adding Traditional Chinese (zh-TW)..."
        $TwLang = New-WinUserLanguageList "zh-TW"
        $NewList.Add($TwLang[0])
    }
    
    # 5. FORCE Rime into zh-TW Input Methods
    # We iterate through the NewList to find zh-TW and inject the IME
    foreach ($Lang in $NewList) {
        if ($Lang.LanguageTag -eq "zh-TW") {
            # Construct the TSF TIP string for Traditional Chinese (0404)
            # Format: 0404:{GUID}{GUID}
            $RimeTip = "0404:$WeaselGuid"
            
            if ($Lang.InputMethodTips -notcontains $RimeTip) {
                Write-Host " - Injecting Rime into zh-TW..."
                $Lang.InputMethodTips.Add($RimeTip)
            }
        }
    }

    # 6. Apply the clean list
    Set-WinUserLanguageList $NewList -Force
    Write-Host "Language list fixed: English + Traditional Chinese Only." -ForegroundColor Green

} catch {
    Write-Warning "Language cleanup encountered an error: $_"
    Write-Warning "You may need to remove Simplified Chinese manually in Settings."
}

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Read-Host "Press Enter to exit..."
