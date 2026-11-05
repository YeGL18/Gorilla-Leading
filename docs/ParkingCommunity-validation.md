# 泊車互助：連線、帳戶及 Android 更新（2026-11-01）

## 今次需同步更新 Windows 後端

手機的新功能需要新的 API；只更新手機不足夠。先停止後端，覆蓋程式碼，保留現有
`community.sqlite3`、`.env.local.json`、`.push` 及原本 `serverSecret`，再重新啟動後端。
**不要刪除資料庫、重建設定或更換 secret**。Tunnel 若仍正常，不用重開。

新增 `/capabilities` 的服務名稱、API 版本及功能識別；儲存網址時會實際查詢，失敗不會覆蓋
已儲存網址，也不會清除登入。接受 HTTPS 主機網址或完整 `/v1/parking-community` 路徑。
這是相容性檢查，並不是憑服務自報名稱就能證明網站可信；只貼上自己 Windows Tunnel 的網址。

新增已登入可用的 `POST /plates/lookup`，只回傳 `available`，不列出用戶、電郵或綁定人數，
每帳戶每小時最多查詢 30 次。它只判斷 App 內有沒有未封鎖的接收者，**不是運輸署車牌查冊**。
發送時仍會再驗證一次，以應付接收者剛解除綁定、封鎖等情況。

訊息加入每位閱覽者的 `mine`；首次發送回傳 `messageId`。手機亦記錄登入回傳的 `userId`，
可用 `authorId` 比對舊格式訊息。曾登入的舊版本可用 `/me/session` 補回身分。
本機首次發送的對話可用首則訊息確認發送者，避免用內容／時間猜測。

## 斷線與車牌草稿

離線、逾時、服務錯誤與驗證失效不會自動抹去手機憑證。真正到期／撤銷的 session 仍須
按「重新驗證登入」；保存 token 不代表過期 token 能繼續存取資料。明確登出或刪除帳戶才清除。
不同服務網址的憑證分開保存，換網址不會把舊 token 自動傳到新主機。

iOS／Android 均可未登入保存本機車牌草稿。登入並確認綁定後才在伺服器生效，才能接收推送。
不會把匿名本機草稿標成已綁定，也不會自動替其他帳戶綁定。

## Android 直接 APK 更新

0.3-test（versionCode 3）起，開啟 App 會查一次版本，設定亦有「檢查應用程式更新」。
此版本需要先手動安裝一次；舊版沒有更新器，不能憑空自動更新。

在啟動後端的同一個 PowerShell 設定（範例路徑請換成實際路徑）：

```powershell
$env:COMMUNITY_ANDROID_APK_PATH = 'C:\GorillaParking\releases\GorillaLeading.apk'
$env:COMMUNITY_ANDROID_VERSION_CODE = '3'
$env:COMMUNITY_ANDROID_VERSION_NAME = '0.3-test'
.\windows\start-backend.ps1
```

之後每次發佈都必須提高 APK 內的 `versionCode`，環境變數須與 APK 一致，並使用同一個
簽署金鑰。以原子替換方式更新 APK，避免下載中途被覆寫。後端只公開指定的一個 APK，沒有檔案目錄瀏覽。
未設定 APK 時 `/android/update` 只回傳 `available:false`，不會假稱已有更新。

更新器要求使用者選擇下載，檢查大小、SHA-256、套件名稱、遞增版本和相同簽章，之後才交給
Android 系統安裝程式；不會靜默安裝。安裝來源授權由使用者在系統設定確認。
安裝權限只在 Debug 直接 APK 測試版本宣告。若將來上 Google Play，應使用 Play In-App Updates，
不可把此直接 APK 安裝方式當成 Play 更新通道。

## Apple 帳戶登入（已追加實作）

Apple Developer 正式 App ID 能力與專用金鑰已完成設定。iOS 原生登入、現有帳戶連結、
伺服器憑證驗證及授權撤銷已實作；最後仍需將新版後端及私密 `.apple` 設定同步到 Windows。
詳細步驟和安全行為見 `docs/AppleLogin.md`。私鑰不在普通更新包內。

官方流程：https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple

## 電郵驗證碼安全檢視

目前實作包含：密碼學隨機六位數、10 分鐘到期、單次使用、最多五次猜測、寄信／驗證限流、
伺服器只儲存 HMAC 摘要、固定長度安全比較、HTTPS 手機連線、強制 STARTTLS 寄信，
以及 iOS Keychain／Android Keystore 加密登入憑證。API 不記錄驗證碼、token 或訊息內容。
兩個手機端均不跟隨 API HTTP 重新導向，避免登入請求被導往另一個網址。

測試涵蓋過期、重播、猜測次數及限流，但**不是安全認證或合規證書**。電郵可能因信箱失守、
釣魚或收件端郵件傳輸問題外洩；STARTTLS 到寄件服務不等於整封郵件端對端加密。
NIST SP 800-63B 不接受電郵作為其 out-of-band authentication 方法；不能宣稱此登入具備
NIST 高保證等級或防釣魚能力。正式上線還需部署、郵件網域／供應商和私隱政策的獨立檢視。

參考：https://pages.nist.gov/800-63-4/sp800-63b.html
