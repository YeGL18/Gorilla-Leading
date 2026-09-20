//
//  LaneGuidanceManager.swift
//  GorillaTranslate
//
//  車道級導航管理器 - 包裝高德 SDK 車道引導功能
//

import Foundation
import SwiftUI
import CoreLocation

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

    var arrows: [String] {
        switch self {
        case .straight: return ["↑"]
        case .left: return ["←"]
        case .straightLeft: return ["↑", "←"]
        case .right: return ["→"]
        case .straightRight: return ["↑", "→"]
        case .leftUturn: return ["↩"]
        case .leftRight: return ["←", "→"]
        case .allDirections: return ["↑", "←", "→"]
        case .rightUturn: return ["↪"]
        case .straightLeftUturn: return ["↑", "↩"]
        case .bus: return ["🚌"]
        case .variable: return ["↔"]
        case .blocked: return ["🚫"]
        }
    }

    var isRecommended: Bool { self != .blocked }

    static func from(code: Int) -> LaneDirection {
        LaneDirection(rawValue: code) ?? .straight
    }
}

// MARK: - 車道數據模型
struct LaneInfo: Identifiable {
    let id = UUID()
    let laneIndex: Int
    let direction: LaneDirection
    let isRecommended: Bool

    /// 從 laneBackInfo 和 laneSelectInfo 解析
    /// laneBackInfo 格式: "1|0|0|4" (每個數字代表一條車道嘅方向)
    /// laneSelectInfo 格式: "0|255|255|255" (0=推薦, 255=不可走)
    static func parse(laneBackInfo: String, laneSelectInfo: String) -> [LaneInfo] {
        let backCodes = laneBackInfo.split(separator: "|").compactMap { Int($0) }
        let selectCodes = laneSelectInfo.split(separator: "|").compactMap { Int($0) }

        return backCodes.enumerated().map { index, code in
            let direction = LaneDirection.from(code: code)
            let selectCode = index < selectCodes.count ? selectCodes[index] : 255
            let isRecommended = selectCode == 0
            return LaneInfo(
                laneIndex: index,
                direction: direction,
                isRecommended: isRecommended
            )
        }
    }
}

// MARK: - 導航步驟
struct NaviStep: Identifiable {
    let id = UUID()
    let instruction: String
    let roadName: String
    let action: String
    let distance: Int // 米
    let duration: Int // 秒
    let lanes: [LaneInfo]
}

// MARK: - 車道導航管理器
@MainActor
class LaneGuidanceManager: ObservableObject {
    static let shared = LaneGuidanceManager()

    @Published var currentLanes: [LaneInfo] = []
    @Published var currentStep: NaviStep?
    @Published var isNavigating = false
    @Published var remainingDistance: Int = 0
    @Published var remainingDuration: Int = 0

    private let webServiceKey = ""

    // MARK: - 模擬車道數據（用於測試 UI）
    func loadMockLaneData() {
        // 模擬不同場景
        let scenarios: [(String, String, String, String)] = [
            // (laneBackInfo, laneSelectInfo, roadName, action)
            ("1|0|0|4", "0|255|255|255", "望京街", "左轉進入阜通東大街"),
            ("1|0|3", "255|255|0", "櫻桃街", "右轉進入連翔道"),
            ("1|2|0|0|4", "255|0|0|0|255", "北四環東路", "直行"),
            ("5|0|4", "0|255|255", "育慧北路", "掉頭"),
        ]

        let scenario = scenarios.randomElement() ?? scenarios[0]
        currentLanes = LaneInfo.parse(laneBackInfo: scenario.0, laneSelectInfo: scenario.1)
        currentStep = NaviStep(
            instruction: "沿\(scenario.2)行駛",
            roadName: scenario.2,
            action: scenario.3,
            distance: Int.random(in: 100...2000),
            duration: Int.random(in: 30...300),
            lanes: currentLanes
        )
    }

    // MARK: - 用 REST API 獲取路線（無車道數據）
    func fetchRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let originStr = "\(origin.longitude),\(origin.latitude)"
        let destStr = "\(destination.longitude),\(destination.latitude)"
        let urlString = "https://restapi.amap.com/v5/direction/driving?origin=\(originStr)&destination=\(destStr)&key=\(webServiceKey)&show_fields=navi,polyline,cost&strategy=32"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let route = json["route"] as? [String: Any],
               let paths = route["paths"] as? [[String: Any]],
               let firstPath = paths.first,
               let steps = firstPath["steps"] as? [[String: Any]] {

                // 解析第一步作為當前步驟
                if let firstStep = steps.first {
                    let roadName = firstStep["road_name"] as? String ?? "未知路段"
                    let instruction = firstStep["instruction"] as? String ?? ""
                    let navi = firstStep["navi"] as? [String: String]
                    let action = navi?["action"] ?? "直行"
                    let distance = Int(firstStep["step_distance"] as? String ?? "0") ?? 0

                    // REST API 沒有車道數據，用模擬數據
                    loadMockLaneData()

                    currentStep = NaviStep(
                        instruction: instruction,
                        roadName: roadName,
                        action: action,
                        distance: distance,
                        duration: 0,
                        lanes: currentLanes
                    )
                }

                // 更新總距離和時間
                if let cost = firstPath["cost"] as? [String: Any] {
                    remainingDistance = Int(firstPath["distance"] as? String ?? "0") ?? 0
                    remainingDuration = Int(cost["duration"] as? String ?? "0") ?? 0
                }
            }
        } catch {
            print("路線獲取失敗: \(error)")
        }
    }

    // MARK: - 模擬導航（循環切換場景）
    func startMockNavigation() {
        isNavigating = true
        loadMockLaneData()

        // 每 5 秒切換一個場景
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadMockLaneData()
            }
        }
    }

    func stopNavigation() {
        isNavigating = false
        currentLanes = []
        currentStep = nil
    }
}
