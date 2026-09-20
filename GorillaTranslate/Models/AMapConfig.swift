//
//  AMapConfig.swift
//  GorillaTranslate
//
//  高德地圖 SDK 配置
//

import Foundation
import AMapFoundationKit
import AMapNaviKit
import AMapLocationKit

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
        // 設定 API Key
        AMapServices.shared().apiKey = iOSKey

        // 啟用 HTTPS
        AMapServices.shared().enableHTTPS = true
    }
}
