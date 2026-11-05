# Apple 登入與帳戶保護

## 已完成

- 正式 App ID `com.gorilla.translation` 已啟用 Sign in with Apple，iOS 簽署已更新。
- 原生 Apple 登入按鈕，透過系統介面驗證；App 不會接收 Apple 密碼。
- 伺服器單次 challenge、5 分鐘時效、nonce、state 檢查，Apple RS256 簽章／issuer／audience／expiry 驗證。
- authorization code 由後端向 Apple 交換並再次核對身分，不相信手機自行提供的 user ID 或電郵。
- 現有帳戶可連結 Apple；需最近 5 分鐘內重新驗證登入，不能憑相同電郵自動合併。
- Apple refresh token 以獨立用途衍生的金鑰加密儲存，不放進 App、Git 或程式更新包。
- 刪除帳戶即撤銷本服務 session、刪除車牌及帳戶資料，同時排入 Apple 授權撤銷。
  背景工作會向 Apple 撤銷授權；網絡失敗時保留加密憑證重試，成功後刪除該憑證。

## Windows 同步（最後啟用步驟）

Mac 上的私密資料夾為 `backend/parking-community/.apple/`，內有 `config.json` 及登入專用 `.p8`。
此資料夾不會包含在普通更新包，也不應經電郵、聊天、公開下載或 Git 傳送。
以 USB 或受保護的直接檔案傳輸，將整個 `.apple` 資料夾複製到 Windows 後端資料夾內。

1. 停止 Windows 後端程式；以新程式檔覆蓋舊程式。
2. **保留** Windows 原有 `community.sqlite3`、`.env.local.json`、`serverSecret` 及 `.push`。
3. 安裝依賴：`python -m pip install -r requirements-push.txt`。
4. 複製 `.apple` 至後端根目錄；相對路徑設定在 Windows 仍可用，不需改金鑰內容。
5. 將該私密目錄的 Windows 權限限制為執行後端的帳戶；例如在後端資料夾的 PowerShell：

```powershell
icacls .apple /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" /T
.\windows\start-backend.ps1
```

`/v1/parking-community/capabilities` 應顯示 `auth.apple: true`。如果是 false，先檢查
Windows 是否有 `.apple/config.json`；如果伺服器報金鑰設定錯誤，檢查檔名、權限及依賴。
不要把私鑰內容貼到聊天或日誌。

原生 iOS Apple 登入不需要固定的網頁回呼網址，因此現有動態 Tunnel 仍可使用。
Android 若日後加入 Apple 網頁登入，則需另設 Services ID 及已登記的 HTTPS 回呼，今次沒有假設它已完成。
現有 Android 電郵帳戶，可先在 iOS 用相同電郵登入，再「連結 Apple 帳戶」，兩邊會維持同一個服務帳戶。

## 使用及測試

新用戶：登入頁 → 使用 Apple 登入 → 系統 Face ID／Apple 驗證 → 登入泊車互助。
舊用戶：先電郵登入／重新驗證 → 車牌與提醒設定 → 連結 Apple 帳戶。
取消 Apple 系統介面不會刪除帳戶；短暫斷線不會自動抹去本機登入憑證。

自動測試使用臨時 RSA／EC 金鑰及隔離資料庫，包含錯誤簽章、issuer、audience、nonce、
過期與重播、帳戶不可冒領／不可自動合併、連結保留車牌、刪除和授權撤銷重試。
這些測試不等於已替真實使用者完成 Face ID；仍需 Windows 更新後作一次實機完整登入。

## 關於「普通 App 的安全做法」

電郵一次性驗證碼是常見的低摩擦登入方式，並非實驗性密碼學。現有隨機產生、單次使用、
有效期限、猜測次數、寄信及驗證限流、HMAC 摘要、HTTPS、SMTP STARTTLS、系統安全儲存等保護保留。
寄出的郵件亦提醒只在 App 輸入，客服不會索取驗證碼。

它仍依賴電郵帳戶安全，不能防止釣魚或信箱被盜，也不是兩步驟驗證或端對端加密郵件。
「NIST 不接受電郵作為指定帶外驗證」指其特定保證等級，並不等於一般 App 使用電郵登入就做錯。
Apple 登入提供系統身分驗證和可驗證的簽署憑證；本服務仍必須保護後端、私鑰、session 及資料庫。

參考：
- https://developer.apple.com/documentation/signinwithapple/verifying-a-user
- https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
- https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html
# Build 6 launch flow

The root view offers the existing native login sheet after the launch animation and first-run introduction finish. It checks local Keychain credentials, without logging users out during a server outage. An unsigned user may dismiss the sheet for the current activation; a later foreground activation offers it again. Background recovery screens suppress presentation until recovery completes.

The login page includes service settings. Build 6 defaults to the verified current Cloudflare Tunnel address; user overrides remain intact. A temporary Tunnel is not a permanent service address.
