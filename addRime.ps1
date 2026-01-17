<#
.SYNOPSIS
    addRime.ps1 (V2) - Working Directory Fix
    Fixes the "Silent Crash" of WeaselDeployer by setting the correct execution context.
#>

# ==========================================
# [AUTO-ELEVATION]
# ==========================================
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $TempScript = "$env:TEMP\addrime_elevated.ps1"
    $MyInvocation.MyCommand.ScriptBlock | Out-File $TempScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TempScript`"" -Verb RunAs
    Exit
}

# ==========================================
# [CONFIG]
# ==========================================
# Target the specific version folder you confirmed exists
$WeaselDir      = "C:\Program Files\Rime\weasel-0.17.4"
$WeaselExe      = "$WeaselDir\WeaselDeployer.exe"
$WeaselClsid    = "{A3F61664-90B7-4EA0-86FA-5056747127C7}"
$BopomofoGuid   = "{B115690A-EA02-48D5-A231-E3578D2FDF80}{B727450D-55D0-4641-8727-2CA8682763F9}"

# ==========================================
# [STEP 1: FORCE REGISTRATION WITH CORRECT PATH]
# ==========================================
Write-Host "--- STEP 1: Verifying Registry ---" -ForegroundColor Cyan
$RegPath = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$WeaselClsid"

if (-not (Test-Path $RegPath)) {
    Write-Host "Registry Key missing. Attempting to fix..." -ForegroundColor Yellow
    
    if (Test-Path $WeaselExe) {
        Write-Host "Executing WeaselDeployer /install..."
        Write-Host "WorkDir: $WeaselDir"
        
        # *** CRITICAL FIX: Set WorkingDirectory so it finds DLLs ***
        $Proc = Start-Process -FilePath $WeaselExe -ArgumentList "/install" -WorkingDirectory $WeaselDir -PassThru -Wait
        
        Write-Host "Process Exit Code: $($Proc.ExitCode)"
        
        # Wait for Windows Registry to flush
        Write-Host "Waiting 3 seconds for Registry update..."
        Start-Sleep -Seconds 3
        
        if (Test-Path $RegPath) {
            Write-Host "[SUCCESS] Weasel is now registered!" -ForegroundColor Green
        } else {
            Write-Error "[FATAL] Registration failed again. Exit Code: $($Proc.ExitCode)"
            Write-Host "Possibility: Missing VC++ Runtime?"
            Pause; Exit
        }
    } else {
        Write-Error "Deployer not found at: $WeaselExe"
        Pause; Exit
    }
} else {
    Write-Host "[OK] Registry Key already exists." -ForegroundColor Green
}

# ==========================================
# [STEP 2: ADD RIME & REMOVE BOPOMOFO]
# ==========================================
Write-Host "`n--- STEP 2: Modifying Language List ---" -ForegroundColor Cyan

try {
    $RimeTip = "0404:$WeaselClsid$WeaselClsid"
    $BopomofoTip = "0404:$BopomofoGuid"
    
    $CurrentList = Get-WinUserLanguageList
    
    # Check zh-TW
    $TwLang = $CurrentList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if (-not $TwLang) {
        Write-Host "Creating zh-TW..."
        $TwLang = (New-WinUserLanguageList "zh-TW")[0]
        $CurrentList.Add($TwLang)
    }

    # Add Rime
    if ($TwLang.InputMethodTips -notcontains $RimeTip) {
        Write-Host "Injecting Rime..."
        $TwLang.InputMethodTips.Add($RimeTip)
    } else {
        Write-Host "Rime already in list."
    }

    # Remove Bopomofo
    if ($TwLang.InputMethodTips -contains $BopomofoTip) {
        Write-Host "Removing Microsoft Bopomofo..."
        $TwLang.InputMethodTips.Remove($BopomofoTip)
    }

    # Apply
    Write-Host "Applying settings..."
    Set-WinUserLanguageList $CurrentList -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Language list updated." -ForegroundColor Green
    
    # Verify
    Start-Sleep -Seconds 1
    $VerifyList = Get-WinUserLanguageList
    $VerifyTw = $VerifyList | Where-Object { $_.LanguageTag -eq "zh-TW" }
    
    if ($VerifyTw.InputMethodTips -contains $RimeTip) {
        Write-Host "VERIFIED: Rime is active!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Rime failed to stick." -ForegroundColor Red
    }

} catch {
    Write-Error "Error: $_"
}

# Cleanup
if (Test-Path "$env:TEMP\addrime_elevated.ps1") { Remove-Item "$env:TEMP\addrime_elevated.ps1" -ErrorAction SilentlyContinue }

Write-Host "`nDone."
Read-Host "Press Enter to exit..."
#V2

