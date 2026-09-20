//
//  AmapNaviTestView.swift
//  GorillaTranslate
//
//  高德原生導航測試頁 - MAMapView + AMapNaviDriveManager + SDK 車道 UI
//

import SwiftUI
import AMapNaviKit
import AMapFoundationKit
import CoreLocation

// MARK: - 高德地圖包裝
struct AmapMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var naviManager: AmapNativeNaviManager

    func makeUIView(context: Context) -> MAMapView {
        AMapConfig.shared.configure()

        let mapView = MAMapView()
        mapView.showsUserLocation = true
        mapView.zoomLevel = 16
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        naviManager.mapView = mapView
        return mapView
    }

    func updateUIView(_ uiView: MAMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(naviManager) }

    class Coordinator: NSObject, MAMapViewDelegate {
        let naviManager: AmapNativeNaviManager
        init(_ naviManager: AmapNativeNaviManager) { self.naviManager = naviManager }

        func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
            if let polyline = overlay as? MAPolyline {
                let renderer = MAPolylineRenderer(polyline: polyline)
                renderer?.strokeColor = UIColor.cyan.withAlphaComponent(0.7)
                renderer?.lineWidth = 6
                return renderer
            }
            return nil
        }

        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            if annotation is MAPointAnnotation {
                let id = "car"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MAAnnotationView
                if view == nil {
                    view = MAAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.image = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    view?.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
                    view?.backgroundColor = UIColor.cyan
                    view?.layer.cornerRadius = 14
                }
                return view
            }
            return nil
        }
    }
}

// MARK: - 高德導航管理器
@MainActor
class AmapNativeNaviManager: NSObject, ObservableObject {
    @Published var isNavigating = false
    @Published var isCalculating = false
    @Published var errorMessage: String?
    @Published var laneImage: UIImage?
    @Published var showLaneGuidance = false
    @Published var currentRoadName: String = ""

    var mapView: MAMapView?
    private var driveManager: AMapNaviDriveManager?
    private var routeLine: MAPolyline?
    private var carAnnotation: MAPointAnnotation?
    private var hasDrawnRoute = false

    override init() {
        super.init()
        driveManager = AMapNaviDriveManager.sharedInstance()
        driveManager?.delegate = self
        driveManager?.addDataRepresentative(self)
        driveManager?.isUseInternalTTS = true
    }

    // MARK: - 開始導航
    func startNavigation(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        guard let driveManager = driveManager else { return }
        isCalculating = true
        errorMessage = nil
        hasDrawnRoute = false

        let o = origin.wgs84ToGCJ02
        let d = destination.wgs84ToGCJ02

        guard let start = AMapNaviPoint.location(withLatitude: CGFloat(o.latitude), longitude: CGFloat(o.longitude)),
              let end = AMapNaviPoint.location(withLatitude: CGFloat(d.latitude), longitude: CGFloat(d.longitude)) else {
            errorMessage = "無法創建導航點"
            isCalculating = false
            return
        }

        driveManager.calculateDriveRoute(withStart: [start], end: [end], wayPoints: nil, drivingStrategy: .motorStrategyMultipleDefault)
    }

    // MARK: - 停止導航
    func stopNavigation() {
        driveManager?.stopNavi()
        isNavigating = false
        isCalculating = false
        showLaneGuidance = false
        laneImage = nil

        if let line = routeLine {
            mapView?.remove(line)
            routeLine = nil
        }
        if let car = carAnnotation {
            mapView?.remove(car)
            carAnnotation = nil
        }
        hasDrawnRoute = false
    }

    // MARK: - 畫路線
    private func drawRoute() {
        guard let route = driveManager?.naviRoute, let mapView = mapView, !hasDrawnRoute else { return }
        hasDrawnRoute = true

        guard let coords = route.routeCoordinates as? [AMapNaviPoint], !coords.isEmpty else { return }

        var points = [CLLocationCoordinate2D]()
        for p in coords {
            points.append(CLLocationCoordinate2D(latitude: CLLocationDegrees(p.latitude), longitude: CLLocationDegrees(p.longitude)))
        }

        let polyline = MAPolyline(coordinates: &points, count: UInt(points.count))
        mapView.add(polyline)
        routeLine = polyline

        // 加車標
        if carAnnotation == nil {
            let ann = MAPointAnnotation()
            mapView.add(ann)
            carAnnotation = ann
        }

        // 自動縮放到路線
        mapView.showOverlays([polyline], edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40), animated: true)
    }

    // MARK: - 更新車位置
    private func updateCarPosition() {
        guard let mapView = mapView, let car = carAnnotation else { return }
        if let loc = mapView.userLocation {
            car.coordinate = loc.coordinate
            mapView.setCenter(loc.coordinate, animated: true)
        }
    }
}

// MARK: - AMapNaviDriveManagerDelegate
extension AmapNativeNaviManager: AMapNaviDriveManagerDelegate {
    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        isCalculating = false
        drawRoute()
        driveManager.startGPSNavi()
        isNavigating = true
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        isCalculating = false
        errorMessage = "路線計算失敗: \(error.localizedDescription)"
    }

    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        stopNavigation()
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, updateNaviInfo naviInfo: AMapNaviInfo?) {
        updateCarPosition()
    }
}

// MARK: - AMapNaviDriveDataRepresentable（車道回調）
extension AmapNativeNaviManager: AMapNaviDriveDataRepresentable {
    func driveManager(_ driveManager: AMapNaviDriveManager, showLaneBackInfo laneBackInfo: String, laneSelectInfo: String) {
        // 用 SDK 內建函數生成車道圖（正確嘅車道數量 + 箭頭）
        if let image = CreateLaneInfoImageWithLaneInfo(laneBackInfo, laneSelectInfo) {
            laneImage = image
            showLaneGuidance = true
        }
    }

    func driveManagerHideLaneInfo(_ driveManager: AMapNaviDriveManager) {
        showLaneGuidance = false
        laneImage = nil
    }
}

// MARK: - 主視圖
struct AmapNaviTestView: View {
    @StateObject private var naviManager = AmapNativeNaviManager()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager

    @State private var pointA: CLLocationCoordinate2D?
    @State private var pointB: CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            // 高德地圖
            AmapMapViewRepresentable(naviManager: naviManager)
                .ignoresSafeArea()

            // 懸浮車道框（導航中 SDK 回調時顯示）
            if naviManager.showLaneGuidance, let image = naviManager.laneImage {
                VStack {
                    VStack(spacing: 4) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                        if !naviManager.currentRoadName.isEmpty {
                            Text(naviManager.currentRoadName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.cyan)
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

            // 控制面板（未導航時）
            if !naviManager.isNavigating {
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        HStack {
                            if naviManager.isCalculating {
                                ProgressView().tint(.cyan)
                                Text("計算路線中...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.cyan)
                            } else {
                                Image(systemName: "map.fill")
                                    .foregroundColor(.cyan)
                                Text("高德原生導航")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                pointA = locationManager.lastLocation?.coordinate
                            }) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.green).frame(width: 16, height: 16)
                                        .overlay(Text("A").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                    Text(pointA != nil ? "已設定 ✓" : "當前位置")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pointA != nil ? Color.green.opacity(0.3) : Color.gray.opacity(0.3)))
                            }

                            Image(systemName: "arrow.right").foregroundColor(.gray)

                            Button(action: {
                                if let dest = destinationManager.selectedDestination {
                                    pointB = dest.coordinate
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.red).frame(width: 16, height: 16)
                                        .overlay(Text("B").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                    Text(pointB != nil ? "已設定 ✓" : "已選目的地")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pointB != nil ? Color.red.opacity(0.3) : Color.gray.opacity(0.3)))
                            }
                        }

                        Button(action: {
                            if let a = pointA, let b = pointB {
                                naviManager.startNavigation(from: a, to: b)
                            }
                        }) {
                            HStack {
                                Image(systemName: "location.north.fill")
                                Text("開始高德導航")
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
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
                    )
                }
            }

            // 停止按鈕（導航中）
            if naviManager.isNavigating {
                VStack {
                    Spacer()
                    Button(action: { naviManager.stopNavigation() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("結束導航")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    .padding(.bottom, 40)
                }
            }

            // 錯誤提示
            if let error = naviManager.errorMessage {
                VStack {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.red.opacity(0.8)))
                        .padding(.top, 100)
                    Spacer()
                }
            }
        }
        .navigationTitle("高德導航測試")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pointA = locationManager.lastLocation?.coordinate
            if let dest = destinationManager.selectedDestination {
                pointB = dest.coordinate
            }
        }
    }
}
