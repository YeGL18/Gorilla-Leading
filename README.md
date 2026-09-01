<div align="center">

# 🦍 GorillaLeading

### 大猩猩泊車記憶 — 智能行車助手

[![Platform](https://img.shields.io/badge/platform-iOS%2026+-black?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square&logo=swift)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?style=flat-square&logo=swift)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/license-Private-red?style=flat-square)](#)

<br/>

一款專為香港駕駛者設計的 iOS 智能行車助手。<br/>
結合即時車速顯示、泊車記憶、動態島 Live Activity、行程預測等功能，<br/>
讓每次駕駛都更輕鬆、更安心。

</div>

---

## ✨ 功能亮點

### 🏎️ 即時車速顯示
- **卡爾曼濾波** 平滑 GPS 車速數據，消除跳動
- **視差動態效果** — 支援陀螺儀傾斜 / G 力感應兩種模式
- **動態 Orb 背景** — 根據日出日落時間自動切換晝夜主題
- **加速音效** — 感應加速時播放引擎聲效
- **專注模式** — 三級省電（輕度 / 平衡 / 極致），長途駕駛不發燙

### 🅿️ 泊車記憶
- **OCR 智能辨識** — 拍照自動識別停車場樓層與車位號碼（Vision 框架）
- **多車位記錄** — 支援同時記錄多個泊車位置
- **地圖標記** — 在地圖上顯示泊車位置，一目了然

### 📱 動態島 & 鎖屏
- **Live Activity** — 動態島即時顯示泊車 / 行車 / 停留狀態
- **計時器** — 自動計算泊車時長
- **狀態切換通知** — 泊車、開車、停留自動切換，帶提示音

### 🧭 行程預測
- **智能預測** — 根據時段（朝早 / 午間 / 下午 / 黃昏 / 深夜）與歷史記錄預測目的地
- **多目的地管理** — 支援自訂目的地，帶顏色標記與距離 / 時間顯示
- **路線規劃** — MapKit 路線計算，顯示預計到達時間

### 🗺️ 香港的士牌考試
- **完整題庫地點** — 涵蓋道路、醫院、政府機構、酒店、地標、交通設施等分類
- **地圖標記** — 在地圖上顯示所有考試地點

### ⚙️ 個人化設定
- **多語言支援** — 繁體中文 / English
- **自訂顏色方案** — 多種 Orb 配色可選
- **地圖樣式** — 切換不同地圖風格
- **啟動動畫** — 大猩猩品牌開場動畫

---

## 🏗️ 技術架構

```
GorillaTranslation/
├── GorillaTranslate/               # 主 App
│   ├── GorillaTranslateApp.swift       # App 入口
│   ├── ContentView.swift               # 主畫面（膠囊導航 + 多頁面）
│   ├── Models/
│   │   ├── LocationManager.swift           # GPS + 卡爾曼濾波
│   │   ├── ParkingRecognitionService.swift # OCR 泊車辨識
│   │   ├── GorillaActivityManager.swift    # Live Activity 管理
│   │   ├── TripPredictor.swift             # 行程預測引擎
│   │   ├── WeatherService.swift            # 日出日落 API
│   │   ├── Destination.swift               # 目的地模型
│   │   ├── SFXPlayer.swift                 # 音效播放
│   │   └── ...
│   ├── Views/
│   │   ├── SpeedView.swift                 # 車速主畫面
│   │   ├── MapView.swift                   # 地圖畫面
│   │   ├── SettingsView.swift              # 設定頁面
│   │   ├── AnimatedBackground.swift        # 動態背景
│   │   ├── LaunchAnimationView.swift       # 啟動動畫
│   │   └── ...
│   └── Extensions/
│       ├── BorderBeam.swift                # 邊框光效
│       └── ColorExtension.swift            # 顏色擴展
├── ParkingTimerWidget/             # Widget Extension
│   ├── GorillaLiveActivity.swift           # 動態島 UI
│   └── ParkingTimerWidget.swift            # Widget 入口
└── Shared/
    └── GorillaActivityAttributes.swift     # 共享 Activity 模型
```

---

## 🛠️ 技術棧

| 技術 | 用途 |
|------|------|
| **SwiftUI** | 全新聲明式 UI 框架 |
| **MapKit** | 地圖渲染與路線規劃 |
| **Vision** | OCR 文字辨識（泊車樓層 / 車位） |
| **ActivityKit** | Live Activity & 動態島 |
| **WidgetKit** | 鎖屏 Widget |
| **CoreLocation** | GPS 定位與地理圍欄 |
| **CoreMotion** | 陀螺儀 & 加速度計（視差效果） |
| **AVFoundation** | 音效播放 |
| **Accelerate** | 高性能數學運算 |

---

## 📋 系統要求

- **iOS 26.0+**
- **Xcode 26+**
- iPhone（需 GPS、陀螺儀、相機）

---

## 🚀 安裝

```bash
# Clone 專案
git clone https://github.com/YeGL18/Gorilla-Leading.git

# 開啟 Xcode
open GorillaTranslation.xcodeproj
```

1. 在 Xcode 中選擇你的 Apple Developer Team
2. 選擇目標裝置（實機推薦，模擬器無 GPS）
3. Build & Run ▶️

---

## 📸 畫面預覽

<div align="center">

| 車速顯示 | 泊車記憶 | 動態島 |
|:---------:|:---------:|:------:|
| 即時車速 + 動態背景 | OCR 辨識 + 地圖標記 | 靈動島狀態切換 |

</div>

---

## 🌟 設計理念

> **「泊車唔使再記，行車唔使再睇。」**

GorillaLeading 的設計靈感來自香港駕駛者的日常痛點：

- 🏢 商場停車場總是忘記停在哪一層
- 🚗 長途駕駛時手機過熱耗電
- 📍 不同時段去不同地方，每次都要重新開導航

我們用 **OCR 自動辨識** 解決泊車記憶問題，用 **專注模式** 解決耗電問題，用 **行程預測** 解決導航問題。

---

## 📄 License

This project is private and proprietary.

---

<div align="center">

**Made with 🦍 in Hong Kong**

</div>
