<#
.SYNOPSIS
    Rime Auto-Installer (V19 - Registry Wait Fix)
    Fixes "Rime not added" issue by waiting for TSF Registry Registration.
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

# Critical GUIDs
$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$WeaselTip     = "0404:$WeaselGuid$WeaselGuid" # Standard TSF format
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

    # --- CRITICAL FIX: WAIT FOR REGISTRY, NOT JUST FILES ---
    Write-Host "Waiting for Registry Registration..." -NoNewline
    $RegPath = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselGuid"
    $Retries = 0; $MaxRetries = 60 # Wait up to 60 seconds
    
    do { 
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
        $Retries++
        $RegExists = Test-Path $RegPath
    } until ($RegExists -or ($Retries -ge $MaxRetries))
    Write-Host "" 

    if (-not $RegExists) { 
        throw "Timed out waiting for Registry Key: $RegPath. Installation might have failed." 
    }
    
    Write-Host "Registry verified. Waiting 3s for stabilization..."
    Start-Sleep -Seconds 3 # Extra buffer for Windows to index the key
    Write-Host "Weasel installed & Registered." -ForegroundColor Green

} else {
    Write-Host "Already installed." -ForegroundColor Green
}

# ==========================================
# [STEP 2: INSTALL CONFIG DATA]
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
# [STEP 3: DEPLOY]
# ==========================================
Write-Host "`n[3/4] Compiling Schemas..."
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue
Stop-Process -Name "WeaselDeployer" -ErrorAction SilentlyContinue
if (Test-Path $DeployerExe) {
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait
}

# ==========================================
# [STEP 4: FIX PERMISSIONS]
# ==========================================
Write-Host "Fixing File Permissions..."
if (Test-Path $RimeUserDir) {
    Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
}

# ==========================================
# [STEP 5: FIX LANGUAGE (3-STAGE)]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List (Registry Checked)..." -ForegroundColor Yellow

try {
    # --- STAGE A: INIT ---
    Write-Host "Stage A: Initializing..."
    $List_A = @()
    # English
    $Curr = Get-WinUserLanguageList
    $En = $Curr | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $List_A += $En
    
    # zh-TW (Reset)
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    $List_A += $Tw
    
    Set-WinUserLanguageList $List_A -Force -ErrorAction Stop
    Write-Host " -> Base initialized."

    # --- STAGE B: INJECT ---
    Write-Host "Stage B: Injecting Rime..."
    # Force a small pause to let Windows refresh its internal list
    Start-Sleep -Milliseconds 500
    
    $List_B = Get-WinUserLanguageList
    $Tw_Target = $List_B | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($Tw_Target) {
        # Check if Windows recognizes the GUID is valid
        if ($Tw_Target.InputMethodTips -notcontains $WeaselTip) {
            $Tw_Target.InputMethodTips.Add($WeaselTip)
            Set-WinUserLanguageList $List_B -Force -ErrorAction Stop
            Write-Host " -> Rime injected."
        } else {
            Write-Host " -> Rime already there."
        }
    }

    # --- STAGE C: CLEANUP ---
    Write-Host "Stage C: Removing Bopomofo..."
    Start-Sleep -Milliseconds 500
    
    $List_C = Get-WinUserLanguageList
    $Tw_Final = $List_C | Where-Object { $_.LanguageTag -eq "zh-TW" }
    $BopomofoTip = "0404:$MsBopomofoGuid"
    
    if ($Tw_Final) {
        if ($Tw_Final.InputMethodTips -contains $WeaselTip) {
             if ($Tw_Final.InputMethodTips -contains $BopomofoTip) {
                $Tw_Final.InputMethodTips.Remove($BopomofoTip)
                Set-WinUserLanguageList $List_C -Force -ErrorAction Stop
                Write-Host " -> Bopomofo removed."
             }
        } else {
            Write-Warning " -> Rime injection check failed. Keeping Bopomofo."
        }
    }

    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " -> UI Locked." -ForegroundColor Green

} catch {
    Write-Error "Language process failed: $_"
}

Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again."
Read-Host "Press Enter to exit..."
#V19
