//
//  AMapConfig.swift
//  GorillaTranslate
//
//  高德地圖 SDK 配置
//

import Foundation

#if !targetEnvironment(simulator)
import AMapFoundationKit
import AMapNaviKit
import AMapLocationKit
#endif

/// 高德地圖 SDK 配置管理器
class AMapConfig {
    static let shared = AMapConfig()

    // MARK: - API Keys
    /// iOS 平台 Key
    private let iOSKey = ""
    /// Web 服務 Key（用於 REST API）
    let webServiceKey = ""

    // MARK: - 初始化
    private init() {}

    /// 配置高德 SDK（必須在 App 啟動時調用）
    func configure() {
        #if !targetEnvironment(simulator)
        // 設定 API Key
        AMapServices.shared().apiKey = iOSKey

        // 啟用 HTTPS
        AMapServices.shared().enableHTTPS = true
        #else
        print("⚠️ AMap SDK 不支援模擬器，跳過配置")
        #endif
    }
}
