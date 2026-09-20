//
//  AmapNaviManager.swift
//  GorillaTranslate
//
//  高德靜默導航管理器 - 只攞車道數據，唔顯示地圖
//

import Foundation
import SwiftUI
import CoreLocation
import AMapNaviKit
import AMapFoundationKit

// MARK: - 車道方向類型
enum LaneDirection: Int, CaseIterable, Identifiable {
    case straight = 0
    case left = 1
    case straightLeft = 2
    case right = 3
    case straightRight = 4
    case leftUturn = 5
    case leftRight = 6
    case allDirections = 7
    case rightUturn = 8
    case straightLeftUturn = 9
    case bus = 21
    case variable = 23
    case blocked = 255

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .straight: return "直行"
        case .left: return "左轉"
        case .straightLeft: return "直行+左轉"
        case .right: return "右轉"
        case .straightRight: return "直行+右轉"
        case .leftUturn: return "左掉頭"
        case .leftRight: return "左轉+右轉"
        case .allDirections: return "全方向"
        case .rightUturn: return "右掉頭"
        case .straightLeftUturn: return "直行+左掉頭"
        case .bus: return "公交車道"
        case .variable: return "可變車道"
        case .blocked: return "不可通行"
        }
    }

    static func from(code: Int) -> LaneDirection {
        LaneDirection(rawValue: code) ?? .straight
    }
}

// MARK: - 高德靜默導航管理器
@MainActor
class AmapNaviManager: NSObject, ObservableObject {
    static let shared = AmapNaviManager()

    // MARK: - Published 狀態
    @Published var isNavigating = false
    @Published var showLaneGuidance = false
    @Published var laneImage: UIImage?        // SDK 生成嘅車道圖
    @Published var laneBackInfo: String = ""
    @Published var laneSelectInfo: String = ""
    @Published var currentRoadName: String = ""
    @Published var nextAction: String = ""
    @Published var remainingDistance: Int = 0   // 米
    @Published var remainingTime: Int = 0       // 秒

    // MARK: - 私有屬性
    private var driveManager: AMapNaviDriveManager?
    private var locationManager: CLLocationManager?
    private var currentDestination: Destination?

    private override init() {
        super.init()
        setupDriveManager()
    }

    // MARK: - 設置導航管理器
    private func setupDriveManager() {
        driveManager = AMapNaviDriveManager.sharedInstance()
        driveManager?.addDataRepresentative(self)
        driveManager?.delegate = self
        // 靜默模式：唔顯示任何 UI
        driveManager?.isUseInternalTTS = false
    }

    // MARK: - 啟動靜默導航
    func startSilentNavigation(to destination: Destination) {
        guard let driveManager = driveManager else { return }

        currentDestination = destination

        // 當前位置
        guard let currentLocation = CLLocationManager().location else {
            print("❌ 無法獲取當前位置")
            return
        }

        let startCoordinate = currentLocation.coordinate
        let endCoordinate = destination.coordinate

        // 高德用 GCJ-02 座標系
        guard let startPOI = AMapNaviPoint.location(withLatitude: CGFloat(startCoordinate.latitude),
                                                     longitude: CGFloat(startCoordinate.longitude)),
              let endPOI = AMapNaviPoint.location(withLatitude: CGFloat(endCoordinate.latitude),
                                                   longitude: CGFloat(endCoordinate.longitude)) else {
            print("❌ 無法創建導航點")
            return
        }

        // 計算路線
        driveManager.calculateDriveRoute(withStart: [startPOI],
                                          end: [endPOI],
                                          wayPoints: nil,
                                          drivingStrategy: .motorStrategyMultipleDefault)

        print("🗺️ 開始計算路線: \(destination.name)")
    }

    // MARK: - 停止導航
    func stopNavigation() {
        driveManager?.stopNavi()
        isNavigating = false
        showLaneGuidance = false
        laneImage = nil
        currentDestination = nil
        print("🛑 導航已停止")
    }

    // MARK: - 更新當前位置嘅車道信息（靜默導航期間自動觸發）
    private func updateLaneInfo(laneBackInfo: String, laneSelectInfo: String) {
        self.laneBackInfo = laneBackInfo
        self.laneSelectInfo = laneSelectInfo

        // 用 SDK 內建函數生成車道圖片
        if let image = CreateLaneInfoImageWithLaneInfo(laneBackInfo, laneSelectInfo) {
            self.laneImage = image
            self.showLaneGuidance = true
            print("🚗 車道信息更新: \(laneBackInfo)")
        }
    }
}

// MARK: - AMapNaviDriveDataRepresentable（接收導航數據）
extension AmapNaviManager: AMapNaviDriveDataRepresentable {

    /// 顯示車道信息回調（路口前自動觸發）
    func driveManager(_ driveManager: AMapNaviDriveManager,
                      showLaneBackInfo laneBackInfo: String,
                      laneSelectInfo: String) {
        updateLaneInfo(laneBackInfo: laneBackInfo, laneSelectInfo: laneSelectInfo)
    }

    /// 隱藏車道信息回調（離開路口後觸發）
    func driveManagerHideLaneInfo(_ driveManager: AMapNaviDriveManager) {
        showLaneGuidance = false
        laneImage = nil
        print("🚗 車道信息已隱藏")
    }
}

// MARK: - AMapNaviDriveManagerDelegate（導航事件）
extension AmapNaviManager: AMapNaviDriveManagerDelegate {

    /// 路線計算成功
    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        print("✅ 路線計算成功，啟動靜默導航")
        // 啟動 GPS 導航（靜默模式，唔顯示 UI）
        driveManager.startGPSNavi()
        isNavigating = true
    }

    /// 路線計算失敗
    func driveManager(_ driveManager: AMapNaviDriveManager,
                      onCalculateRouteFailure error: Error) {
        print("❌ 路線計算失敗: \(error.localizedDescription)")
    }

    /// 導航到達目的地
    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        print("🏁 已到達目的地")
        stopNavigation()
    }

    /// 導航信息更新（實時位置、剩餘距離等）
    func driveManager(_ driveManager: AMapNaviDriveManager,
                      updateNaviInfo naviInfo: AMapNaviInfo?) {
        guard let info = naviInfo else { return }
        remainingDistance = info.segmentRemainDistance
        remainingTime = info.segmentRemainTime

        // 更新當前路名
        if let roadName = info.nextRoadName, !roadName.isEmpty {
            currentRoadName = roadName
        }
    }
}
