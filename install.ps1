<#
.SYNOPSIS
    Rime Auto-Installer (V20 - Robust V18 Logic)
    Back to V18 structure, but with a retry loop for Rime injection.
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

# GUID Definitions
$WeaselGuid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}{A3F61664-90B7-4EA0-86FA-5056747127C7}"
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
# [STEP 5: FIX LANGUAGE (ROBUST V18 LOGIC)]
# ==========================================
Write-Host "`n[4/4] Sanitizing Language List (Robust Mode)..." -ForegroundColor Yellow

$RimeTip = "0404:$WeaselGuid"
$BopomofoTip = "0404:$MsBopomofoGuid"

try {
    # --- STAGE A: BASE INITIALIZATION ---
    # Ensure [English, zh-TW (Default Bopomofo)]
    Write-Host "Stage A: Initializing Base Languages..."
    
    $List_A = @()
    # English
    $Curr = Get-WinUserLanguageList
    $En = $Curr | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    if (-not $En) { $En = (New-WinUserLanguageList "en-US")[0] }
    $List_A += $En
    
    # zh-TW (Will default to Microsoft Bopomofo)
    $Tw = (New-WinUserLanguageList "zh-TW")[0]
    $List_A += $Tw
    
    Set-WinUserLanguageList $List_A -Force -ErrorAction Stop
    Write-Host " -> Base initialized."

    # --- STAGE B: INJECT RIME (WITH RETRY) ---
    Write-Host "Stage B: Injecting Rime..."
    
    $RetryCount = 0
    $MaxRetries = 5
    $RimeAdded = $false

    while (-not $RimeAdded -and $RetryCount -lt $MaxRetries) {
        $RetryCount++
        Write-Host "   Attempt $RetryCount of $MaxRetries..."
        
        # 1. Reload List
        $List_B = Get-WinUserLanguageList
        $Tw_Target = $List_B | Where-Object { $_.LanguageTag -eq "zh-TW" }
        
        if ($Tw_Target) {
             # 2. Try Add
             if ($Tw_Target.InputMethodTips -notcontains $RimeTip) {
                $Tw_Target.InputMethodTips.Add($RimeTip)
                try {
                    Set-WinUserLanguageList $List_B -Force -ErrorAction Stop
                } catch {
                    Write-Warning "   Set-WinUserLanguageList failed on this attempt."
                }
             }
        }
        
        # 3. VERIFY: Did it stick?
        Start-Sleep -Seconds 2
        $CheckList = Get-WinUserLanguageList
        $CheckTw = $CheckList | Where-Object { $_.LanguageTag -eq "zh-TW" }
        
        if ($CheckTw.InputMethodTips -contains $RimeTip) {
            $RimeAdded = $true
            Write-Host " -> Rime successfully injected!" -ForegroundColor Green
        } else {
            Write-Warning " -> Rime not found in list yet. Retrying..."
        }
    }

    if (-not $RimeAdded) {
        throw "Failed to add Rime after multiple attempts. Aborting removal of Bopomofo."
    }

    # --- STAGE C: REMOVE BOPOMOFO ---
    Write-Host "Stage C: Removing Bopomofo..."
    
    $List_C = Get-WinUserLanguageList
    $Tw_Final = $List_C | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    # SAFETY CHECK: Only remove Bopomofo if Rime is confirmed present
    if ($Tw_Final.InputMethodTips -contains $RimeTip) {
        if ($Tw_Final.InputMethodTips -contains $BopomofoTip) {
            $Tw_Final.InputMethodTips.Remove($BopomofoTip)
            Set-WinUserLanguageList $List_C -Force -ErrorAction Stop
            Write-Host " -> Microsoft Bopomofo removed."
        }
    } else {
        Write-Error "CRITICAL: Rime is missing from the final list. Keeping Bopomofo to ensure usability."
    }

    # Lock UI
    Set-WinUILanguageOverride -Language "zh-TW"
    Write-Host " -> UI Locked to zh-TW." -ForegroundColor Green

} catch {
    Write-Error "Language process failed: $_"
}

# Final Cleanup
Stop-Process -Name "WeaselServer" -ErrorAction SilentlyContinue -Force

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Write-Host "Please Sign Out and Sign In again."
Read-Host "Press Enter to exit..."
#V20

