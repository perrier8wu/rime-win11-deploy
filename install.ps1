<#
.SYNOPSIS
    Rime Auto-Installer (Final Integrated Version)
    
    Workflow:
    1. Install Rime via Winget.
    2. Download & Deploy custom Rime configuration.
    3. Configure Windows Input Methods using the SYSTEM-VERIFIED ID.
       (ID: 0404:{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}{3D02CAB6-2B8E-4781-BA20-1C9267529467})
    4. Remove Microsoft Bopomofo, leaving only Rime.
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
# 實測有效的系統 ID (The ID verified by your GUI experiment)
$VerifiedWeaselId = "0404:{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}{3D02CAB6-2B8E-4781-BA20-1C9267529467}"
$BopomofoId       = "0404:{B115690A-EA02-48D5-A231-E3578D2FDF80}{B2F9C502-1742-11D4-9790-0080C882687E}"

# 路徑與網址
$TargetVersion = "0.17.4"
$WeaselDir     = "C:\Program Files\Rime\weasel-$TargetVersion"
$DeployerExe   = "$WeaselDir\WeaselDeployer.exe" 
$RimeUserDir   = "$env:APPDATA\Rime"
$ProgDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/data.zip"
$UserDataUrl   = "https://github.com/perrier8wu/rime-win11-deploy/raw/main/rime_user_data.zip"

# ==========================================
# [STEP 1] 安裝小狼毫 (Winget)
# ==========================================
Write-Host "`n--- [1/4] Installing Weasel (Winget) ---" -ForegroundColor Cyan

if (-not (Test-Path $DeployerExe)) {
    try {
        # 靜默安裝
        winget install --id Rime.Weasel --version $TargetVersion -h --accept-source-agreements --accept-package-agreements --force
    } catch {
        Write-Error "Winget install failed. Please check internet connection."; Pause; Exit
    }
    
    # 等待檔案系統寫入完成
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

if (-not (Test-Path $DeployerExe)) { Write-Error "Critical: Installer failed to create files."; Pause; Exit }

# ==========================================
# [STEP 2] 下載設定檔並部署 (Config & Deploy)
# ==========================================
Write-Host "`n--- [2/4] Deploying Configuration ---" -ForegroundColor Cyan

$TempProg = "$env:TEMP\rime_prog.zip"
$TempUser = "$env:TEMP\rime_user.zip"

try {
    Write-Host "Downloading configs..."
    Invoke-RestMethod -Uri $ProgDataUrl -OutFile $TempProg
    Invoke-RestMethod -Uri $UserDataUrl -OutFile $TempUser

    Write-Host "Extracting files..."
    Expand-Archive $TempProg -DestinationPath "$WeaselDir\data" -Force
    Expand-Archive $TempUser -DestinationPath $RimeUserDir -Force

    # 執行部署 (這步很重要，它會產生 bin 檔)
    Write-Host "Running Weasel Deployer..."
    Start-Process $DeployerExe -ArgumentList "/deploy" -Wait

    # 權限修正 (避免手動部署時被拒絕)
    Write-Host "Fixing User Permissions..."
    if (Test-Path $RimeUserDir) {
        Start-Process icacls -ArgumentList "`"$RimeUserDir`" /grant Users:(OI)(CI)F /T /Q" -NoNewWindow -Wait
    }
} catch {
    Write-Error "Deployment failed: $_"
} finally {
    Remove-Item $TempProg, $TempUser -ErrorAction SilentlyContinue
}

# ==========================================
# [STEP 3] 設定輸入法 (The Core Fix)
# ==========================================
Write-Host "`n--- [3/4] Setting Input Methods (Using Verified ID) ---" -ForegroundColor Cyan

try {
    $CurrentList = Get-WinUserLanguageList
    
    # 鎖定繁體中文 (保留現有物件)
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -like "zh*" -and $_.InputMethodTips -like "0404:*" } | Select-Object -First 1

    # 如果沒安裝中文，幫忙裝上去
    if (-not $TwLang) {
        Write-Host "Adding Traditional Chinese Language..."
        $TwLang = (New-WinUserLanguageList "zh-Hant-TW")[0]
        $CurrentList.Add($TwLang)
    }

    $Modified = $false

    # A. 加入我們驗證過的小狼毫 ID
    if ($TwLang.InputMethodTips -notcontains $VerifiedWeaselId) {
        Write-Host " + Adding Weasel (Verified System ID)"
        $TwLang.InputMethodTips.Add($VerifiedWeaselId)
        $Modified = $true
    } else {
        Write-Host " = Weasel is already present."
    }

    # B. 移除微軟注音
    if ($TwLang.InputMethodTips -contains $BopomofoId) {
        Write-Host " - Removing Microsoft Bopomofo"
        $TwLang.InputMethodTips.Remove($BopomofoId)
        $Modified = $true
    }

    # 提交變更
    if ($Modified) {
        Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
        Write-Host "Input methods updated successfully." -ForegroundColor Green
    } else {
        Write-Host "No changes needed." -ForegroundColor Green
    }

} catch {
    Write-Error "Language Setup Failed: $_"
}

# ==========================================
# [STEP 4] 收尾 (Finalize)
# ==========================================
Write-Host "`n--- [4/4] Finalizing ---" -ForegroundColor Cyan

# 強制 UI 語言為繁中 (可選)
Set-WinUILanguageOverride -Language "zh-TW"
Write-Host "UI Locked to zh-TW."

# 重啟相關服務以確保生效
Stop-Process -Name "WeaselServer", "WeaselDeployer" -ErrorAction SilentlyContinue -Force

Write-Host "`n[SUCCESS] Installation & Setup Complete!" -ForegroundColor Green
Write-Host "Current Keyboard Layout:"
$FinalList = Get-WinUserLanguageList | Where-Object LanguageTag -like "zh*"
Write-Host $FinalList.InputMethodTips

Read-Host "Press Enter to exit..."
#V24

