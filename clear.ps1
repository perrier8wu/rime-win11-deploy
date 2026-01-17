# 1. Get current language list
$LangList = Get-WinUserLanguageList

# 2. Filter out Rime (Weasel) from all languages
# Weasel's internal GUID always contains "A3F61664"
foreach ($Lang in $LangList) {
    if ($Lang.InputMethodTips -match "A3F61664") {
        Write-Host "Found phantom Rime entry in language: $($Lang.LanguageTag)" -ForegroundColor Yellow
        $Lang.InputMethodTips = $Lang.InputMethodTips | Where-Object { $_ -notmatch "A3F61664" }
    }
}

# 3. Apply the clean list back to Windows
# This forces the taskbar to refresh immediately
Set-WinUserLanguageList $LangList -Force

Write-Host "Phantom Rime input method removed!" -ForegroundColor Green

