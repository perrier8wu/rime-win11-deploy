小狼毫蝦米輸入法 Windows 11 自動部署
自動部署小狼毫並安裝蝦米輸入法

⚡ 安裝 (Install)
請以 系統管理員身分 (Administrator) 開啟 PowerShell，貼上並執行以下指令：

PowerShell

irm https://perrier8wu.github.io/rime-win11-deploy/install.ps1 | iex


🗑️ 移除 (Uninstall)
若需完整移除小狼毫、清除設定檔並恢復微軟注音，請執行：

PowerShell

irm https://perrier8wu.github.io/rime-win11-deploy/uninstall.ps1 | iex

(注意：腳本會自動請求提權，請確保網路連線正常以進行檔案下載。)

使用提示
1. 配合 ParyEmacs 的Autohotkey, 可用CapsLock 與 左Ctrl+Space 切換語音輸入法
2. ~ 可用來注音反查蝦米碼
