<#
.SYNOPSIS
    Rime Auto-Installer (V9 - Strict Language Whitelist)
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

# Weasel TSF GUID (Double GUID is required for full TSF registration)
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
# [STEP 5: STRICT LANGUAGE RESET (V9)]
# ==========================================
Write-Host "`n[5/5] Enforcing Strict Language Policy..." -ForegroundColor Yellow
Write-Host "Policy: [English + Traditional Chinese (Rime)] ONLY."

try {
    # 1. Define the CLEAN List (Empty initially)
    $CleanList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]

    # 2. Find an existing English language to keep (Prefer US, or whatever user has)
    $CurrentList = Get-WinUserLanguageList
    $EnglishLang = $CurrentList | Where-Object { $_.LanguageTag -like "en*" } | Select-Object -First 1
    
    if (-not $EnglishLang) {
        Write-Host " - No English found, adding en-US default."
        $EnglishLang = New-WinUserLanguageList "en-US"
        $EnglishLang = $EnglishLang[0]
    } else {
        Write-Host " - Keeping English: $($EnglishLang.LanguageTag)"
    }
    $CleanList.Add($EnglishLang)

    # 3. Create/Prepare Traditional Chinese (zh-TW)
    # We create a fresh object to ensure no junk data from previous states
    $TwLangList = New-WinUserLanguageList "zh-TW"
    $TwLang = $TwLangList[0]
    
    # 4. Inject Rime into zh-TW
    $RimeTip = "0404:$WeaselGuid"
    Write-Host " - Injecting Rime into zh-TW..."
    
    # Check if MS Bopomofo is there, we keep it as backup or just add Rime? 
    # Usually New-WinUserLanguageList adds MS Bopomofo by default. We append Rime.
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        $TwLang.InputMethodTips.Add($RimeTip)
    }
    
    $CleanList.Add($TwLang)

    # 5. EXECUTE THE OVERWRITE
    # This command replaces the ENTIRE system list with our CleanList.
    # Anything not in CleanList (like zh-CN) is effectively deleted.
    Set-WinUserLanguageList $CleanList -Force
    
    Write-Host "Language list successfully reset!" -ForegroundColor Green

} catch {
    Write-Error "Language enforcement failed: $_"
    Write-Host "Please manually remove Simplified Chinese in Settings if it persists."
}

Write-Host "`nSuccess! Boshiamy is ready." -ForegroundColor Green
Read-Host "Press Enter to exit..."

