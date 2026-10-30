# Windows 常駐部署（測試用）

把泊車互助後端裝到一台**不關機的 Windows 電腦**上，手機就可以隨時連線，
MacBook 隨時闔蓋。僅供測試，不是生產部署。

## 安裝前準備

1. **把整個 `backend/parking-community` 資料夾拷到 Windows**（例如 `C:\GorillaParking`）。
   不要把 `.env.local.json` 拷過去（內有 Gmail 密碼），到 Windows 重新建立即可。
   `.push` 資料夾（內有 FCM / APNs 私鑰）**無法重新下載**，要用 USB 或區域網路親自拷過去
   ——不要經雲盤、聊天工具或電郵傳送。
2. 安裝 **Python 3.11+**：<https://www.python.org/downloads/>
   安裝時勾選 **「Add python.exe to PATH」**。
3. 安裝 **cloudflared**：在 PowerShell 執行 `winget install Cloudflare.cloudflared`，
   或到官網下載 <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/>
4. 準備一個 **Gmail 應用程式密碼**（16 碼）：Google 帳號 → 安全性 → 兩步驟驗證 → 應用程式密碼。

## 設定與啟動（第一次）

**① 建立設定檔**（PowerShell，在 `C:\GorillaParking` 目錄）：

```powershell
python run_local.py --init
notepad .env.local.json
```

只填兩欄，存檔（`serverSecret` 已自動生成，不要改）：

```json
{
  "gmailAddress": "你的@gmail.com",
  "gmailAppPassword": "16碼應用程式密碼",
  "serverSecret": "（已自動生成，不要改）"
}
```

**② 啟動後端** — 開一個 PowerShell 視窗：

```powershell
cd C:\GorillaParking\windows
.\start-backend.ps1
```

視窗保持開著（可最小化）。日誌在 `windows\backend.log`。

**③ 啟動 tunnel** — 另開一個 PowerShell 視窗，執行：

```powershell
cloudflared tunnel --url http://127.0.0.1:8787
```

視窗保持開著（可最小化）。輸出裡會出現 `https://xxx.trycloudflare.com`。

**④ 取得網址** — 第三個 PowerShell 視窗：

```powershell
cd C:\GorillaParking\windows
.\show-url.ps1
```

網址會**複製到剪貼簿**（格式 `https://xxx.trycloudflare.com/v1/parking-community`）。
打開手機 App →「車牌與提醒設定」→「測試伺服器網址」→ 貼上 → 儲存 → 登入。

## 開機自動啟動（建議設定一次）

1. `Win + R` 輸入 `shell:startup` Enter — 打開「啟動」資料夾。
2. 右鍵 → 新增 → 捷徑 → 輸入：

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File C:\GorillaParking\windows\start-backend.ps1
   ```

   名稱叫「泊車後端」。用同樣方法再建一條捷徑指向 tunnel（第 ③ 步那條 `cloudflared ...` 指令
   前面加 `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -Command`），
   名稱叫「泊車Tunnel」。

之後每次開機（登入後）兩個服務會自動啟動。
⚠️ **tunnel 每次重啟網址都會變** — 重開機後跑一次 `show-url.ps1`，把新網址貼到手機 App 並重新登入。

## 推播設定（FCM + APNs，選做但建議）

程式碼不用改動；只加依賴和憑證設定，手機才能收到背景推播。

**① 安裝推播依賴**（PowerShell，在 `C:\GorillaParking` 目錄）：

```powershell
pip install -r requirements-push.txt
```

**② 建立憑證資料夾** `C:\GorillaParking\.push\`，放入兩個私鑰檔
（從 Mac 用 USB / 區域網路拷過來；檔名要一致）：

- `firebase-service-account.json` —— Firebase 服務帳號私鑰
- `AuthKey_XXXXXXXXXX.p8` —— Apple APNs 密鑰（檔名以 `AuthKey_` 開頭、`.p8` 結尾；
  如果拿到的是 .zip 要先解壓）

**③ 建立** `C:\GorillaParking\.push\config.json`（用記事本，數值照填）：

```json
{
  "fcm": {
    "serviceAccountFile": "C:/GorillaParking/.push/firebase-service-account.json"
  },
  "apns": {
    "keyFile": "C:/GorillaParking/.push/AuthKey_XXXXXXXXXX.p8",
    "keyId": "（10 個字元的 Key ID）",
    "teamId": "JVL487RN2F",
    "bundleId": "com.gorilla.translation"
  }
}
```

**④ 重啟後端**（關閉舊視窗再跑 `start-backend.ps1`），然後驗證 —— 瀏覽器開：

```
http://127.0.0.1:8787/v1/parking-community/capabilities
```

見到 `"apns": true, "fcm": true` 就成功。如果顯示 `false` 或後端啟動報錯，
檢查上面檔案名與路徑是否一致。

## 注意事項

- **Windows 電源設定要設為「永不睡眠」**（設定 → 系統 → 電源），否則手機連不上。
- 首次啟動時如果 Windows 防火牆彈出詢問，按「允許」（實際上不需要入站連線）。
- `.env.local.json` 含 Gmail 應用程式密碼，**不要上傳、不要分享**、不要放進 Git。
- tunnel 把服務暴露到公網，網址是隨機的但仍屬公開；這是測試用途，正式上線請換
  正式網域＋TLS 反向代理。
- 停止服務：關閉那兩個 PowerShell 視窗，並刪除「啟動」資料夾裡的捷徑。
