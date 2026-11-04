# 構建與部署

## 分支與專案結構

`main` 的程式碼可能落後於測試版。目前較新的 iOS／Android／互助後端原始碼位於 [`codex/parking-community`](https://github.com/YeGL18/Gorilla-Leading/tree/codex/parking-community)，部分近期修改仍未發布。先檢查分支實際檔案，再照該分支的說明構建。

| 路徑 | 用途 |
| --- | --- |
| `GorillaTranslate/` | SwiftUI iOS App、地圖、泊車、到訪與儀表 |
| `ParkingTimerWidget/`、`Shared/` | Widget／Live Activity 及共用資料型別 |
| `android/` | 原生 Android 泊車互助測試客戶端 |
| `backend/parking-community/` | Python／SQLite API、郵件驗證與推送服務 |
| `Tests/` | 功能檢查及獨立 UI 測試工具 |
| `docs/`、`design/` | 整合說明、功能界線及設計紀錄 |

## iOS

```sh
git clone https://github.com/YeGL18/Gorilla-Leading.git
cd Gorilla-Leading
git switch codex/parking-community
open GorillaTranslation.xcodeproj
```

選擇 `GorillaTranslate` scheme 及目標裝置。最低部署版本為 iOS 26.0，但目前開發程式碼引用較新 SDK，請使用能編譯該分支所有條件式 API 的 Xcode；最低執行系統版本與最低構建 SDK 並不相同。

真機簽署需改成自己的 Team、Bundle ID、App Group 及 provisioning 設定。Apple 登入、推送和 CarPlay 各有獨立的 Apple 能力／批准要求，複製原始碼不會自動取得權限。

```sh
xcodebuild -project GorillaTranslation.xcodeproj \
  -scheme GorillaTranslate \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/gorilla-build build
```

模擬器可注入定位測試版面與流程；真實 GPS、背景執行、震動、相機、推送及 AC 實際連線仍需對應裝置驗證。發布到 App Store Connect 使用 Xcode 的 Archive／Distribute App，並確認簽署與出口合規資料。

## Android

需要 Java 17 與 Android SDK 35，最低 Android 15。以對應分支的 `android/README.md` 為準。

```sh
cd android
./gradlew -PcommunityApiUrl=https://YOUR-HOST/v1/parking-community \
  assembleDebug testDebugUnitTest
```

Firebase 用戶端設定放在被 Git 忽略的 `android/app/google-services.json`。FCM 私鑰只放後端，不能打包到 APK。Debug APK 不等於已完成商店發布與正式簽署的版本。

## 泊車互助後端

需要 Python 3.11+，以及郵件／推送相應配置；請閱讀開發分支中的 `backend/parking-community/README.md` 及 `windows/README-windows.md`。

```sh
python3 backend/parking-community/run_local.py --init
```

在本機填寫產生的私密配置。對外服務應經 HTTPS；Cloudflare Quick Tunnel 的網址重建後可能改變，正式使用宜配置穩定網址及受管理部署。Windows 常駐電腦是目前測試部署方式，不代表倉庫附帶可供任何人使用的公開服務。

## 憑證與資料

不要提交 `.env`、Apple／APNs `.p8`、FCM 服務帳戶、SMTP 密碼、簽署檔、使用者資料庫、真實行程匯出或含私人資料的截圖。公開範例一律使用佔位值與模擬資料。

## 驗證

測試腳本以各分支實際檔案為準。SwiftUI 介面改動至少需成功構建；感測、到訪判定與背景提醒還需要實際駕駛或裝置測試。請在停車後檢查結果，不要邊駕駛邊操作測試介面。
