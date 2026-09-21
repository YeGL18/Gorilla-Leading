//
//  LaneNavigationTestView.swift
//  GorillaTranslate
//
//  路線模擬測試頁 - 模擬 A→B 路線移動 + SDK 車道箭頭
//


#if !targetEnvironment(simulator)
import SwiftUI
import MapKit
import CoreLocation
import AMapNaviKit

// MARK: - 選點模式
enum PointSelectionMode {
    case none, selectingA, selectingB
}

// MARK: - 路線步驟
struct RouteStep {
    let coordinate: CLLocationCoordinate2D
    let action: String       // 高德 navi.action
    let roadName: String
    let laneBackInfo: String // 車道背景
    let laneSelectInfo: String // 車道推薦
}

// MARK: - 模擬導航
@MainActor
class NavigationSimulator: ObservableObject {
    @Published var isActive = false
    @Published var currentLocation: CLLocationCoordinate2D
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var progress: Double = 0
    @Published var showLaneGuidance = false
    @Published var laneImage: UIImage?
    @Published var currentRoadName: String = ""
    @Published var currentAction: String = ""

    private var routeSteps: [RouteStep] = []
    private var stepIndex = 0
    private var timer: Timer?
    var coordinateIndex = 0

    init() {
        self.currentLocation = CLLocationCoordinate2D(latitude: 22.316667, longitude: 114.175631)
    }

    func startSimulation(to destination: CLLocationCoordinate2D) {
        isActive = true
        coordinateIndex = 0
        stepIndex = 0
        progress = 0

        Task {
            await fetchRoute(from: currentLocation, to: destination)
        }
    }

    func stopSimulation() {
        isActive = false
        timer?.invalidate()
        timer = nil
        routeCoordinates = []
        routeSteps = []
        coordinateIndex = 0
        showLaneGuidance = false
        laneImage = nil
    }

    private func fetchRoute(from origin: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) async {
        let o = origin.wgs84ToGCJ02
        let d = dest.wgs84ToGCJ02
        let urlString = "https://restapi.amap.com/v5/direction/driving?origin=\(o.longitude),\(o.latitude)&destination=\(d.longitude),\(d.latitude)&key=&show_fields=navi,polyline,cost&strategy=32"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let route = json["route"] as? [String: Any],
               let paths = route["paths"] as? [[String: Any]],
               let firstPath = paths.first,
               let steps = firstPath["steps"] as? [[String: Any]] {

                var coords = [CLLocationCoordinate2D]()
                var parsedSteps = [RouteStep]()

                for step in steps {
                    let roadName = step["road_name"] as? String ?? ""
                    let navi = step["navi"] as? [String: String]
                    let action = navi?["action"] ?? "直行"

                    // 根據動作生成對應嘅車道數據
                    let lane = laneDataForAction(action)

                    if let polyline = step["polyline"] as? String {
                        let points = polyline.split(separator: ";")
                        for (i, point) in points.enumerated() {
                            let parts = point.split(separator: ",")
                            if parts.count == 2, let lon = Double(parts[0]), let lat = Double(parts[1]) {
                                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                coords.append(coord)
                                // 每個步驟嘅第一個點作為觸發點
                                if i == 0 {
                                    parsedSteps.append(RouteStep(
                                        coordinate: coord,
                                        action: action,
                                        roadName: roadName,
                                        laneBackInfo: lane.0,
                                        laneSelectInfo: lane.1
                                    ))
                                }
                            }
                        }
                    }
                }

                routeCoordinates = coords
                routeSteps = parsedSteps
                if let first = coords.first { currentLocation = first }
                startMoving()
            }
        } catch {
            print("路線失敗: \(error)")
        }
    }

    // MARK: - 根據導航動作生成車道數據
    private func laneDataForAction(_ action: String) -> (String, String) {
        // 返回 (laneBackInfo, laneSelectInfo)
        // laneBackInfo: 每條車道嘅方向類型
        // laneSelectInfo: 0=推薦, 255=唔推薦
        switch action {
        case "左转":
            return ("1|0|0", "0|255|255")           // 左轉 | 直行 | 直行，推薦左轉
        case "右转":
            return ("0|0|3", "255|255|0")           // 直行 | 直行 | 右轉，推薦右轉
        case "向左前方行驶":
            return ("2|0|0", "0|255|255")           // 左前方 | 直行 | 直行
        case "向右前方行驶":
            return ("0|0|4", "255|255|0")           // 直行 | 直行 | 右前方
        case "左转掉头":
            return ("5|0|0", "0|255|255")           // 掉頭 | 直行 | 直行
        case "向左后方行驶":
            return ("5|0|0", "0|255|255")           // 掉頭
        case "右转掉头":
            return ("0|0|8", "255|255|0")           // 直行 | 直行 | 右掉頭
        case "进入环岛":
            return ("0|0|0", "0|0|0")               // 環島，全部直行
        case "驶出环岛":
            return ("0|0|3", "255|255|0")           // 出環島，靠右
        default: // 直行、到達目的地 等
            return ("0|0|0|0", "0|0|0|0")           // 四車道直行
        }
    }

    private func startMoving() {
        guard !routeCoordinates.isEmpty else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.coordinateIndex < self.routeCoordinates.count - 1 {
                    self.coordinateIndex += 1
                    self.currentLocation = self.routeCoordinates[self.coordinateIndex]
                    self.progress = Double(self.coordinateIndex) / Double(self.routeCoordinates.count - 1)

                    // 檢查係咪到達下一個步驟觸發點
                    self.checkStepTransition()
                } else {
                    self.showLaneGuidance = false
                    self.stopSimulation()
                }
            }
        }
    }

    // MARK: - 檢查步驟轉換
    private func checkStepTransition() {
        // 揾到當前位置最近嘅步驟
        for (i, step) in routeSteps.enumerated() {
            if i <= stepIndex { continue }
            let dist = distanceBetween(currentLocation, step.coordinate)
            if dist < 50 { // 50 米內觸發
                stepIndex = i
                showLaneForStep(step)
                break
            }
        }
    }

    private func showLaneForStep(_ step: RouteStep) {
        currentRoadName = step.roadName
        currentAction = step.action

        // 用 SDK 函數生成車道圖
        if let image = CreateLaneInfoImageWithLaneInfo(step.laneBackInfo, step.laneSelectInfo) {
            laneImage = image
            showLaneGuidance = true
        }

        // 3 秒後隱藏
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.showLaneGuidance = false
        }
    }

    private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}

// MARK: - 主視圖
struct LaneNavigationTestView: View {
    @StateObject private var simulator = NavigationSimulator()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var pointA: CLLocationCoordinate2D?
    @State private var pointB: CLLocationCoordinate2D?
    @State private var selectionMode: PointSelectionMode = .none
    @State private var mapCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 22.316667, longitude: 114.175631)

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $mapPosition) {
                    // 路線
                    if !simulator.routeCoordinates.isEmpty {
                        MapPolyline(coordinates: simulator.routeCoordinates)
                            .stroke(.cyan.opacity(0.5), lineWidth: 5)
                    }

                    // 已走過
                    if simulator.isActive && simulator.coordinateIndex > 1 {
                        let passed = Array(simulator.routeCoordinates[0...simulator.coordinateIndex])
                        MapPolyline(coordinates: passed)
                            .stroke(.green, lineWidth: 4)
                    }

                    // A
                    if let a = pointA {
                        Annotation("A", coordinate: a) {
                            Circle().fill(Color.green).frame(width: 24, height: 24)
                                .overlay(Text("A").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                        }
                    }

                    // B
                    if let b = pointB {
                        Annotation("B", coordinate: b) {
                            Circle().fill(Color.red).frame(width: 24, height: 24)
                                .overlay(Text("B").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                        }
                    }

                    // 車
                    if simulator.isActive {
                        Annotation("", coordinate: simulator.currentLocation) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Circle().fill(Color.cyan))
                                .shadow(radius: 3)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange { context in
                    mapCenter = context.camera.centerCoordinate
                }
            }

            // 懸浮車道框（SDK 生成嘅車道圖）
            if simulator.showLaneGuidance, let image = simulator.laneImage {
                VStack {
                    VStack(spacing: 4) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                        if !simulator.currentRoadName.isEmpty {
                            Text(simulator.currentRoadName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                        if !simulator.currentAction.isEmpty {
                            Text(simulator.currentAction)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .cyan.opacity(0.3), radius: 10, y: 4)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // 十字準星
            if selectionMode != .none {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Rectangle().fill(Color.white).frame(width: 2, height: 20)
                            Rectangle().fill(Color.white).frame(width: 20, height: 2)
                        }
                        .offset(y: -10)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        Text(selectionMode == .selectingA ? "移動地圖選擇 A 點" : "移動地圖選擇 B 點")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                        Spacer()
                    }
                    .padding(.top, 50)

                    HStack(spacing: 12) {
                        Button("取消") { selectionMode = .none }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Capsule().fill(Color.gray.opacity(0.6)))

                        Button("確認選點") {
                            if selectionMode == .selectingA { pointA = mapCenter }
                            else { pointB = mapCenter }
                            selectionMode = .none
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(Color.cyan))
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            }

            // 底部面板
            if selectionMode == .none {
                VStack(spacing: 0) {
                    Spacer()

                    if simulator.isActive {
                        ProgressView(value: simulator.progress)
                            .progressViewStyle(.linear)
                            .tint(.cyan)
                            .padding(.horizontal, 20).padding(.bottom, 8)
                    }

                    VStack(spacing: 16) {
                        HStack {
                            Circle().fill(simulator.isActive ? Color.green : Color.gray).frame(width: 8, height: 8)
                            Text(simulator.isActive ? "模擬中..." : "路線模擬")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            if simulator.isActive {
                                Text("\(Int(simulator.progress * 100))%")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                        }

                        HStack(spacing: 12) {
                            Button(action: { selectionMode = .selectingA }) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.green).frame(width: 16, height: 16)
                                        .overlay(Text("A").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                    Text(pointA != nil ? "已設定 ✓" : "選 A 點")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pointA != nil ? Color.green.opacity(0.3) : Color.gray.opacity(0.3)))
                            }

                            Image(systemName: "arrow.right").foregroundColor(.gray)

                            Button(action: { selectionMode = .selectingB }) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.red).frame(width: 16, height: 16)
                                        .overlay(Text("B").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                    Text(pointB != nil ? "已設定 ✓" : "選 B 點")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pointB != nil ? Color.red.opacity(0.3) : Color.gray.opacity(0.3)))
                            }
                        }

                        if simulator.isActive {
                            Button(action: { simulator.stopSimulation() }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("停止模擬")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.8)))
                            }
                        } else {
                            Button(action: {
                                if let a = pointA { simulator.currentLocation = a }
                                if let b = pointB { simulator.startSimulation(to: b) }
                            }) {
                                HStack {
                                    Image(systemName: "road.lanes")
                                    Text("開始路線模擬")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(pointA != nil && pointB != nil ? Color.cyan : Color.gray.opacity(0.5))
                                )
                            }
                            .disabled(pointA == nil || pointB == nil)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
                    )
                }
                .transition(.move(edge: .bottom))
            }
        }
        .navigationTitle("路線模擬測試")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let loc = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 22.316667, longitude: 114.175631)
            pointA = loc
            simulator.currentLocation = loc
            if let dest = destinationManager.selectedDestination {
                pointB = dest.coordinate
            }
        }
    }
}

#else
// 模擬器 stub
import SwiftUI
struct LaneNavigationTestView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.north.line")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("路線模擬測試")
                .font(.title2)
            Text("AMap SDK 不支援 arm64 模擬器\n請使用真機測試")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .navigationTitle("路線模擬測試")
    }
}
#endif
