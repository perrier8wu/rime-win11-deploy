<#
.SYNOPSIS
    Rime Auto-Installer (Final Production Version)
    
    Features:
    1. Installs Weasel (Winget).
    2. Deploys Configuration (Download & Deploy).
    3. Input Method: Adds the specific "System-Verified" Weasel ID (A3F4...).
    4. Input Method: Removes Microsoft Bopomofo.
    5. Cleanup: Specifically removes "Simplified Chinese" (zh-Hans-CN) based on diagnostic data.
#>

# ==========================================
# [0] 權限檢查 (Auto-Elevation)
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\rime_install_final.ps1"
    $MyInvocation.MyCommand.ScriptBlock | Out-File $TempScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [CONFIGURATION]
# ==========================================
# 實測有效的系統 ID (Verified from your system)
$VerifiedWeaselId = "0404:{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}{3D02CAB6-2B8E-4781-BA20-1C9267529467}"
$BopomofoId       = "0404:{B115690A-EA02-48D5-A231-E3578D2FDF80}{B2F9C502-1742-11D4-9790-0080C882687E}"

# 根據診斷結果鎖定的移除目標
$TargetToRemove   = "zh-Hans-CN"

# 檔案路徑與網址
$TargetVersion = "0.17.4"
$WeaselDir     = "C:\Program Files\Rime\weasel-$TargetVersion"
$DeployerExe   = "$WeaselDir\WeaselDeployer.exe" 
$RimeUserDir   = "$env:APPDATA\Rime"
$ProgDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [STEP 1] 安裝小狼毫 (Winget)
# ==========================================
Write-Host "`n--- [1/5] Installing Weasel ---" -ForegroundColor Cyan

if (-not (Test-Path $DeployerExe)) {
    try {
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Winget install failed. Please check internet connection."; Pause; Exit
    }
    
    Write-Host "Waiting for file system..." -NoNewline
    for ($i=0; $i -lt 30; $i++) { 
        if (Test-Path $DeployerExe) { break }
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
    }
    Write-Host ""
} else {
    Write-Host "Weasel already installed. Skipping." -ForegroundColor Yellow
}

# ==========================================
# [STEP 2] 下載與部署設定檔
# ==========================================
Write-Host "`n--- [2/5] Deploying Configuration ---" -ForegroundColor Cyan
$TempProg = "$env:TEMP\rime_prog.zip"
$TempUser = "$env:TEMP\rime_user.zip"

try {
    Write-Host "Downloading configs..."
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProg
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUser

    Write-Host "Extracting files..."
    Expand-Archive $TempProg -DestinationPath "$WeaselDir\data" -Force
    Expand-Archive $TempUser -DestinationPath $RimeUserDir -Force

    Write-Host "Running Weasel Deployer..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait

    # 修正權限 (確保 User 可以讀寫設定)
    if (Test-Path $RimeUserDir) {
        Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
    }
} catch {
    Write-Error "Deploy failed: $_"
} finally {
    Remove-Item $TempProg, $TempUser -ErrorAction SilentlyContinue
}

# ==========================================
# [STEP 3] 設定輸入法 (核心邏輯)
# ==========================================
Write-Host "`n--- [3/5] Configuring Input Methods ---" -ForegroundColor Cyan

$CurrentList = Get-WinUserLanguageList

# 1. 鎖定繁體中文 (保留現有設定)
$TwLang = $CurrentList | Where-Object { $_.LanguageTag -like "zh*" -and $_.InputMethodTips -like "0404:*" } | Select-Object -First 1

if (-not $TwLang) {
    Write-Host "Adding Traditional Chinese..."
    $TwLang = (New-WinUserLanguageList "zh-Hant-TW")[0]
    $CurrentList.Add($TwLang)
}

$Modified = $false

# 2. 加入實測有效的小狼毫 ID (A3F4...)
if ($TwLang.InputMethodTips -notcontains $VerifiedWeaselId) {
    Write-Host " + Adding Weasel (Verified ID)"
    $TwLang.InputMethodTips.Add($VerifiedWeaselId)
    $Modified = $true
}

# 3. 移除微軟注音
if ($TwLang.InputMethodTips -contains $BopomofoId) {
    Write-Host " - Removing Bopomofo"
    $TwLang.InputMethodTips.Remove($BopomofoId)
    $Modified = $true
}

# 4. 提交輸入法變更 (確保中文設定正確)
if ($Modified) {
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    Write-Host "Input methods updated." -ForegroundColor Green
}

# ==========================================
# [STEP 4] 精確移除「簡體中文」 (zh-Hans-CN)
# ==========================================
Write-Host "`n--- [4/5] Removing Simplified Chinese ---" -ForegroundColor Cyan

# 重新獲取清單以確保資料最新
$CleanupList = Get-WinUserLanguageList

# 尋找目標：zh-Hans-CN
$TargetLang = $CleanupList | Where-Object { $_.LanguageTag -eq $TargetToRemove }

if ($TargetLang) {
    Write-Host "Target Found: $($TargetLang.LocalizedName) [$($TargetLang.LanguageTag)]"
    Write-Host "Removing..."
    
    # 執行移除
    $CleanupList.Remove($TargetLang)
    
    # 提交變更
    Set-WinUserLanguageList $CleanupList -Force -ErrorAction Stop
    Write-Host "Simplified Chinese removed successfully." -ForegroundColor Green
} else {
    Write-Host "Target '$TargetToRemove' not found. System is clean." -ForegroundColor Green
}

# ==========================================
# [STEP 5] 完成
# ==========================================
Write-Host "`n--- [5/5] Finalizing ---" -ForegroundColor Cyan

# 鎖定 UI 語言
Set-WinUILanguageOverride -Language "zh-TW"
# 重啟服務
Stop-Process -Name "WeaselServer", "WeaselDeployer" -ErrorAction SilentlyContinue -Force

Write-Host "`n[SUCCESS] Installation & Setup Complete!" -ForegroundColor Green
Write-Host "Final Language List:"
Get-WinUserLanguageList | Format-Table -Property LanguageTag, LocalizedName -AutoSize

Read-Host "Press Enter to exit..."
#V25

