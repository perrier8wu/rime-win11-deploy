Rime (Weasel) Windows 11 自動部署
本專案專為 Windows 11 打造，能自動安裝 Rime (小狼毫)、套用設定檔，並修正輸入法無法正確掛載的問題。執行後系統將自動移除微軟注音與簡體中文，僅保留「英文」與「小狼毫」。

⚡ 安裝 (Install)
請以 系統管理員身分 (Administrator) 開啟 PowerShell，貼上並執行以下指令：

PowerShell

irm https://perrier8wu.github.io/rime-win11-deploy/install.ps1 | iex


🗑️ 移除 (Uninstall)
若需完整移除小狼毫、清除設定檔並恢復微軟注音，請執行：

PowerShell

irm https://perrier8wu.github.io/rime-win11-deploy/uninstall.ps1 | iex

(注意：腳本會自動請求提權，請確保網路連線正常以進行檔案下載。)
